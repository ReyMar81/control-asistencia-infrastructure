import * as fs from "node:fs";
import * as path from "node:path";
import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

const config = new pulumi.Config();
const awsRegion = (config.get("awsRegion") ?? "us-east-2") as aws.Region;
const projectName = config.get("projectName") ?? "control-asistencia";
const environment = config.get("environment") ?? "dev";
const vpcCidr = config.get("vpcCidr") ?? "10.10.0.0/16";
const publicSubnetCidr = config.get("publicSubnetCidr") ?? "10.10.1.0/24";
const availabilityZone = config.get("availabilityZone") ?? "us-east-2a";
const instanceType = config.get("instanceType") ?? "t3.micro";
const configuredAmiId = config.get("amiId") ?? "";
const gitBranch = config.get("gitBranch") ?? "main";
const backendRepoUrl =
  config.get("backendRepoUrl") ??
  "https://github.com/ReyMar81/backend-control-asistencia.git";
const frontendRepoUrl =
  config.get("frontendRepoUrl") ??
  "https://github.com/ReyMar81/frontend-control-asistencia.git";
const dbUser = config.get("dbUser") ?? "ca_app";
const dbName = config.get("dbName") ?? "control_asistencia";
const clientUrl = config.get("clientUrl") ?? "http://localhost:5173";
const backendPort = config.getNumber("backendPort") ?? 3000;
const dbPassword = config.requireSecret("dbPassword");
const jwtSecret = config.requireSecret("jwtSecret");
const githubDeployBranch = config.get("githubDeployBranch") ?? gitBranch;
const githubFrontendRepository =
  config.get("githubFrontendRepository") ??
  "ReyMar81/frontend-control-asistencia";
const githubBackendRepository =
  config.get("githubBackendRepository") ??
  "ReyMar81/backend-control-asistencia";

const provider = new aws.Provider("aws", { region: awsRegion });
const tags = {
  Project: projectName,
  Environment: environment,
  ManagedBy: "pulumi",
};

const vpc = new aws.ec2.Vpc(
  "vpc",
  {
    cidrBlock: vpcCidr,
    enableDnsSupport: true,
    enableDnsHostnames: true,
    tags: { ...tags, Name: `${projectName}-vpc` },
  },
  { provider },
);

const internetGateway = new aws.ec2.InternetGateway(
  "internet-gateway",
  {
    vpcId: vpc.id,
    tags: { ...tags, Name: `${projectName}-igw` },
  },
  { provider },
);

const publicSubnet = new aws.ec2.Subnet(
  "public-subnet",
  {
    vpcId: vpc.id,
    cidrBlock: publicSubnetCidr,
    availabilityZone,
    mapPublicIpOnLaunch: true,
    tags: { ...tags, Name: `${projectName}-public-subnet` },
  },
  { provider },
);

const publicRouteTable = new aws.ec2.RouteTable(
  "public-route-table",
  {
    vpcId: vpc.id,
    routes: [{ cidrBlock: "0.0.0.0/0", gatewayId: internetGateway.id }],
    tags: { ...tags, Name: `${projectName}-public-rt` },
  },
  { provider },
);

new aws.ec2.RouteTableAssociation(
  "public-route-table-association",
  { subnetId: publicSubnet.id, routeTableId: publicRouteTable.id },
  { provider },
);

const frontendSecurityGroup = new aws.ec2.SecurityGroup(
  "frontend-security-group",
  {
    vpcId: vpc.id,
    description: "Public HTTP and HTTPS access for the frontend",
    ingress: [
      { description: "HTTP from Internet", protocol: "tcp", fromPort: 80, toPort: 80, cidrBlocks: ["0.0.0.0/0"] },
      { description: "HTTPS from Internet", protocol: "tcp", fromPort: 443, toPort: 443, cidrBlocks: ["0.0.0.0/0"] },
    ],
    egress: [{ description: "Internet and backend access", protocol: "-1", fromPort: 0, toPort: 0, cidrBlocks: ["0.0.0.0/0"] }],
    tags: { ...tags, Name: `${projectName}-frontend-sg` },
  },
  { provider },
);

const backendSecurityGroup = new aws.ec2.SecurityGroup(
  "backend-security-group",
  {
    vpcId: vpc.id,
    description: "Backend API access only from the frontend security group",
    ingress: [
      {
        description: "API only from frontend",
        protocol: "tcp",
        fromPort: backendPort,
        toPort: backendPort,
        securityGroups: [frontendSecurityGroup.id],
      },
    ],
    egress: [{ description: "Internet for updates and SSM", protocol: "-1", fromPort: 0, toPort: 0, cidrBlocks: ["0.0.0.0/0"] }],
    tags: { ...tags, Name: `${projectName}-backend-sg` },
  },
  { provider },
);

const ec2Role = new aws.iam.Role(
  "ec2-ssm-role",
  {
    assumeRolePolicy: JSON.stringify({
      Version: "2012-10-17",
      Statement: [{ Action: "sts:AssumeRole", Effect: "Allow", Principal: { Service: "ec2.amazonaws.com" } }],
    }),
    tags: { ...tags, Name: `${projectName}-ec2-ssm-role` },
  },
  { provider },
);

new aws.iam.RolePolicyAttachment(
  "ec2-ssm-policy",
  {
    role: ec2Role.name,
    policyArn: "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  },
  { provider },
);

const instanceProfile = new aws.iam.InstanceProfile(
  "ec2-instance-profile",
  { role: ec2Role.name, tags: { ...tags, Name: `${projectName}-ec2-ssm-profile` } },
  { provider },
);

const githubOidcProvider = new aws.iam.OpenIdConnectProvider(
  "github-oidc-provider",
  {
    url: "https://token.actions.githubusercontent.com",
    clientIdLists: ["sts.amazonaws.com"],
    thumbprintLists: ["6938fd4d98bab03faadb97b34396831e3780aea1"],
    tags: { ...tags, Name: `${projectName}-github-oidc` },
  },
  { provider },
);

const accountId = aws.getCallerIdentityOutput({}, { provider }).accountId;
const ssmDocumentArn = pulumi.interpolate`arn:aws:ssm:${awsRegion}::document/AWS-RunShellScript`;
const ssmInstanceArn = pulumi.interpolate`arn:aws:ec2:${awsRegion}:${accountId}:instance/*`;

function githubTrustPolicy(repository: string): pulumi.Output<string> {
  return pulumi.all([githubOidcProvider.arn]).apply(([providerArn]) =>
    JSON.stringify({
      Version: "2012-10-17",
      Statement: [{
        Effect: "Allow",
        Action: "sts:AssumeRoleWithWebIdentity",
        Principal: { Federated: providerArn },
        Condition: {
          StringEquals: { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
          StringLike: {
            "token.actions.githubusercontent.com:sub":
              `repo:${repository}:ref:refs/heads/${githubDeployBranch}`,
          },
        },
      }],
    }),
  );
}

function createGithubDeployRole(name: string, repository: string, component: string) {
  const role = new aws.iam.Role(
    name,
    {
      name: `${projectName}-github-${component}-deploy`,
      assumeRolePolicy: githubTrustPolicy(repository),
      tags: { ...tags, Name: `${projectName}-github-${component}-deploy` },
    },
    { provider },
  );
  new aws.iam.RolePolicy(
    `${name}-policy`,
    {
      role: role.id,
      policy: pulumi.all([ssmDocumentArn, ssmInstanceArn]).apply(([documentArn, instanceArn]) =>
        JSON.stringify({
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Action: "ssm:SendCommand",
              Resource: documentArn,
            },
            {
              Effect: "Allow",
              Action: "ssm:SendCommand",
              Resource: instanceArn,
              Condition: {
                StringEquals: { "ssm:resourceTag/Name": `${projectName}-${component}` },
              },
            },
            {
              Effect: "Allow",
              Action: ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"],
              Resource: "*",
            },
          ],
        }),
      ),
    },
    { provider },
  );
  return role;
}

const githubFrontendDeployRole = createGithubDeployRole(
  "github-frontend-deploy",
  githubFrontendRepository,
  "frontend",
);
const githubBackendDeployRole = createGithubDeployRole(
  "github-backend-deploy",
  githubBackendRepository,
  "backend",
);

const ami = configuredAmiId
  ? pulumi.output(configuredAmiId)
  : aws.ec2.getAmiOutput({
      mostRecent: true,
      owners: ["amazon"],
      filters: [
        { name: "name", values: ["al2023-ami-2023.*-x86_64"] },
        { name: "state", values: ["available"] },
        { name: "architecture", values: ["x86_64"] },
        { name: "root-device-type", values: ["ebs"] },
        { name: "virtualization-type", values: ["hvm"] },
      ],
    }).id;

const templateRoot = path.resolve(process.cwd(), "..", "cloud-init", "user-data");
const backendTemplate = fs.readFileSync(path.join(templateRoot, "backend.yaml.tmpl"), "utf8");
const frontendTemplate = fs.readFileSync(path.join(templateRoot, "frontend.yaml.tmpl"), "utf8");

function renderTemplate(template: string, values: Record<string, string>): string {
  return template.replace(/\$\{([A-Z0-9_]+)\}/g, (match, key: string) => {
    if (!(key in values)) {
      throw new Error(`Missing Cloud-Init value: ${key}`);
    }
    return values[key];
  });
}

const backendUserData = pulumi
  .all({ dbPassword, jwtSecret })
  .apply(({ dbPassword: password, jwtSecret: secret }) =>
    renderTemplate(backendTemplate, {
      BACKEND_REPO_URL: backendRepoUrl,
      GIT_BRANCH: gitBranch,
      DB_USER: dbUser,
      DB_PASSWORD: password,
      DB_NAME: dbName,
      JWT_SECRET: secret,
      CLIENT_URL: clientUrl,
      PORT: String(backendPort),
    }),
  );

const backend = new aws.ec2.Instance(
  "backend",
  {
    ami,
    instanceType,
    subnetId: publicSubnet.id,
    vpcSecurityGroupIds: [backendSecurityGroup.id],
    iamInstanceProfile: instanceProfile.name,
    associatePublicIpAddress: true,
    userData: backendUserData,
    metadataOptions: { httpTokens: "required", httpEndpoint: "enabled" },
    rootBlockDevice: { volumeSize: 30, volumeType: "gp3", deleteOnTermination: true },
    tags: { ...tags, Name: `${projectName}-backend` },
  },
  { provider },
);

const frontendUserData = backend.privateIp.apply((backendPrivateIp) =>
  renderTemplate(frontendTemplate, {
    FRONTEND_REPO_URL: frontendRepoUrl,
    GIT_BRANCH: gitBranch,
    BACKEND_PRIVATE_IP: backendPrivateIp,
  }),
);

const frontend = new aws.ec2.Instance(
  "frontend",
  {
    ami,
    instanceType,
    subnetId: publicSubnet.id,
    vpcSecurityGroupIds: [frontendSecurityGroup.id],
    iamInstanceProfile: instanceProfile.name,
    associatePublicIpAddress: true,
    userData: frontendUserData,
    metadataOptions: { httpTokens: "required", httpEndpoint: "enabled" },
    rootBlockDevice: { volumeSize: 30, volumeType: "gp3", deleteOnTermination: true },
    tags: { ...tags, Name: `${projectName}-frontend` },
  },
  { provider },
);

export const frontendPublicIp = frontend.publicIp;
export const frontendPrivateIp = frontend.privateIp;
export const backendPublicIp = backend.publicIp;
export const backendPrivateIp = backend.privateIp;
export const applicationUrl = frontend.publicIp.apply((ip) => `http://${ip}`);
export const githubFrontendDeployRoleArn = githubFrontendDeployRole.arn;
export const githubBackendDeployRoleArn = githubBackendDeployRole.arn;
