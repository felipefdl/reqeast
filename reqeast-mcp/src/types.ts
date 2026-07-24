export interface MCPContext {
  version: number;
  timestamp: string;
  sessionsDir: string;
  selectedProjectId: string | null;
  selectedRequestId: string | null;
  recentExecutions: RecentExecution[];
}

export interface RecentExecution {
  requestId: string;
  requestName: string;
  projectName: string;
  method: string;
  url: string;
  statusCode: number;
  elapsedMs: number;
  timestamp: string;
}

export interface MCPProject {
  id: string;
  name: string;
  emoji: string | null;
  iconURL: string | null;
  color: string;
  folderId: string | null;
}

export interface MCPRequestFolder {
  id: string;
  projectId: string;
  name: string;
  color: string;
}

export interface MCPRequest {
  id: string;
  projectId: string;
  name: string;
  type: string;
  folderId: string | null;
  sortOrder: number;
  httpData: MCPHttpRequestData | null;
  tcpData: MCPTcpRequestData | null;
  udpData: MCPUdpRequestData | null;
}

export interface MCPHttpRequestData {
  method: string;
  url: string;
  params: MCPKeyValueEntry[];
  headers: MCPKeyValueEntry[];
  bodyType: string;
  bodyContent: string;
  bodyFormData: MCPKeyValueEntry[];
  authType: string;
  followRedirects: boolean;
  timeoutSeconds: number;
  sslVerify: boolean;
  httpVersion: string;
  maxRedirects: number;
  encodeUrl: boolean;
}

export interface MCPTcpRequestData {
  host: string;
  port: number;
  useTls: boolean;
  encoding: string;
}

export interface MCPUdpRequestData {
  host: string;
  port: number;
  bindPort: number;
  timeout: number;
}

export interface MCPKeyValueEntry {
  key: string;
  value: string;
  enabled: boolean;
}

export interface MCPProjectsExport {
  version: number;
  timestamp: string;
  projects: MCPProject[];
  requests: MCPRequest[];
  requestFolders: MCPRequestFolder[];
}

export interface MCPEnvironmentsExport {
  version: number;
  timestamp: string;
  environments: MCPEnvironment[];
}

export interface MCPEnvironment {
  id: string;
  projectId: string;
  name: string;
  variables: MCPEnvironmentVariable[];
  isActive: boolean;
}

export interface MCPEnvironmentVariable {
  key: string;
  value: string;
  isSecret: boolean;
  enabled: boolean;
}

export interface MCPHistoryEntry {
  id: string;
  requestId: string;
  method: string;
  url: string;
  statusCode: number;
  elapsedMs: number;
  bodySize: number;
  timestamp: string;
}

export interface MCPResponseMeta {
  statusCode: number;
  statusText: string;
  headers: MCPKeyValueEntry[];
  elapsedMs: number;
  bodySize: number;
  finalUrl: string;
  httpVersion: string;
  remoteAddr: string | null;
  timestamp: string;
  timing: MCPTimingBreakdown | null;
  certificate: MCPCertificateInfo | null;
  sizeInfo: MCPSizeInfo | null;
  redirectChain: MCPRedirectEntry[];
}

export interface MCPTimingBreakdown {
  dnsLookupMs: number;
  connectionMs: number;
  downloadMs: number;
  totalMs: number;
}

export interface MCPCertificateInfo {
  subjectCn: string | null;
  issuerCn: string | null;
  validUntil: string | null;
}

export interface MCPSizeInfo {
  requestHeadersSize: number;
  requestBodySize: number;
  responseHeadersSize: number;
  responseBodySize: number;
  responseCompressedSize: number;
}

export interface MCPRedirectEntry {
  url: string;
  statusCode: number;
}

export interface MCPStoredCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  expires: string | null;
  httpOnly: boolean;
  secure: boolean;
  sameSite: string | null;
}
