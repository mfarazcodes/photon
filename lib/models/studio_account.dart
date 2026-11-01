import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Subscription tier and its GPU quota.
enum PlanTier {
  indie('INDIE LAB', 'INDIE', '\$0 / mo', '64 GPU-hrs', 64, Color(0xFF9A9AA4)),
  pro('STUDIO PRO', 'PRO', '\$49 / mo', '1,000 GPU-hrs', 1000, Color(0xFF8A2BE2)),
  enterprise(
    'ENTERPRISE CLUSTER',
    'ENT',
    '\$299 / mo',
    'Unlimited Dedicated Nodes',
    10000,
    Color(0xFFFF2D78),
  );

  const PlanTier(this.label, this.tag, this.price, this.quota, this.gpuHours, this.color);

  final String label;

  /// Short form for tight spaces (the header pill).
  final String tag;
  final String price;
  final String quota;

  /// GPU render hours included per month.
  final int gpuHours;
  final Color color;
}

/// How the user proves who they are.
enum AuthMethod {
  passkey('WebAuthn Passkey · Hardware Enclave', 'Passkey'),
  oauthGithub('GitHub OAuth 2.0 + PKCE', 'GitHub OAuth'),
  ssoSaml('Enterprise SAML 2.0 SSO', 'SAML SSO'),
  apiKey('Local CLI / MCP Bearer Token', 'CLI Bearer');

  const AuthMethod(this.label, this.shortLabel);

  final String label;
  final String shortLabel;
}

@immutable
class ApiKeyRecord {
  const ApiKeyRecord({
    required this.id,
    required this.label,
    required this.prefix,
    required this.secret,
    required this.created,
    required this.lastUsed,
    required this.scopes,
  });

  final String id;
  final String label;

  /// Visible head of the key, safe to show masked keys with.
  final String prefix;

  /// The full bearer token. Shown only on request.
  final String secret;
  final String created;
  final String lastUsed;
  final List<String> scopes;

  /// `pht_mcp_98a7f2••••••••c41e`: the secret with its middle hidden.
  String get masked => '$prefix••••••••${secret.substring(secret.length - 4)}';

  ApiKeyRecord copyWith({String? prefix, String? secret, String? lastUsed}) => ApiKeyRecord(
    id: id,
    label: label,
    prefix: prefix ?? this.prefix,
    secret: secret ?? this.secret,
    created: created,
    lastUsed: lastUsed ?? this.lastUsed,
    scopes: scopes,
  );
}

@immutable
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.device,
    required this.location,
    required this.ip,
    required this.protocol,
    required this.isCurrent,
    required this.lastActive,
  });

  final String id;
  final String device;
  final String location;
  final String ip;
  final String protocol;

  /// The session this window is running in; it cannot be revoked.
  final bool isCurrent;
  final String lastActive;
}

@immutable
class StudioAccount {
  const StudioAccount({
    required this.displayName,
    required this.handle,
    required this.email,
    required this.role,
    required this.organization,
    required this.workspaceId,
    required this.tier,
    required this.authMethod,
    required this.twoFactorEnabled,
    required this.hardwareKeyBound,
    required this.gpuHoursUsed,
    required this.storageUsedGb,
    required this.storageLimitGb,
    required this.apiKeys,
    required this.sessions,
  });

  /// The seeded studio account.
  factory StudioAccount.initial() => const StudioAccount(
    displayName: 'Mohd Faraz',
    handle: '@mfarazcodes',
    email: 'faraz@photon.studio',
    role: 'Lead Rendering Architect',
    organization: 'Photon Spatial Labs',
    workspaceId: 'WS-IND-0492',
    tier: PlanTier.pro,
    authMethod: AuthMethod.passkey,
    twoFactorEnabled: true,
    hardwareKeyBound: true,
    gpuHoursUsed: 842.5,
    storageUsedGb: 128.4,
    storageLimitGb: 500.0,
    apiKeys: [
      ApiKeyRecord(
        id: 'key_mcp',
        label: 'Stitch MCP Bridge Key',
        prefix: 'pht_mcp_98a7f2',
        secret: 'pht_mcp_98a7f2d3b6e04f19a85c7d2e41b0c41e',
        created: '12 Sep 2026',
        lastUsed: '4m ago',
        scopes: ['designs:read', 'render:submit'],
      ),
      ApiKeyRecord(
        id: 'key_eng',
        label: 'Local C++ Engine Socket Key',
        prefix: 'pht_eng_44b1d0',
        secret: 'pht_eng_44b1d07a92c1e5f38d6b0a47e219889a',
        created: '30 Sep 2026',
        lastUsed: '1h ago',
        scopes: ['engine:socket', 'frames:stream'],
      ),
    ],
    sessions: [
      ActiveSession(
        id: 'ses_local',
        device: 'Windows 11 · Motobook 60 (Local Studio)',
        location: 'Local workstation',
        ip: '127.0.0.1',
        protocol: 'WebSocket · ws://127.0.0.1:8765',
        isCurrent: true,
        lastActive: 'now',
      ),
      ActiveSession(
        id: 'ses_node',
        device: 'NVIDIA L40S Render Node · ap-south-1',
        location: 'Mumbai, IN',
        ip: '10.42.8.19',
        protocol: 'gRPC · mTLS',
        isCurrent: false,
        lastActive: '12m ago',
      ),
      ActiveSession(
        id: 'ses_mcp',
        device: 'Claude Code MCP Agent · stdio',
        location: 'Local process',
        ip: '127.0.0.1',
        protocol: 'MCP · stdio',
        isCurrent: false,
        lastActive: '2m ago',
      ),
    ],
  );

  final String displayName;
  final String handle;
  final String email;
  final String role;
  final String organization;
  final String workspaceId;
  final PlanTier tier;
  final AuthMethod authMethod;
  final bool twoFactorEnabled;
  final bool hardwareKeyBound;
  final double gpuHoursUsed;
  final double storageUsedGb;
  final double storageLimitGb;
  final List<ApiKeyRecord> apiKeys;
  final List<ActiveSession> sessions;

  /// Two-letter monogram for the avatar.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  StudioAccount copyWith({
    String? displayName,
    String? role,
    String? organization,
    PlanTier? tier,
    AuthMethod? authMethod,
    bool? twoFactorEnabled,
    bool? hardwareKeyBound,
    List<ApiKeyRecord>? apiKeys,
    List<ActiveSession>? sessions,
  }) => StudioAccount(
    displayName: displayName ?? this.displayName,
    handle: handle,
    email: email,
    role: role ?? this.role,
    organization: organization ?? this.organization,
    workspaceId: workspaceId,
    tier: tier ?? this.tier,
    authMethod: authMethod ?? this.authMethod,
    twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
    hardwareKeyBound: hardwareKeyBound ?? this.hardwareKeyBound,
    gpuHoursUsed: gpuHoursUsed,
    storageUsedGb: storageUsedGb,
    storageLimitGb: storageLimitGb,
    apiKeys: apiKeys ?? this.apiKeys,
    sessions: sessions ?? this.sessions,
  );
}
