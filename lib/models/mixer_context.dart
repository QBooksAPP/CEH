class MixerAssignment {
  const MixerAssignment({
    required this.clientId,
    required this.clientName,
    required this.projectId,
    required this.projectName,
    required this.isActive,
    this.updatedAt,
  });

  final int clientId;
  final String clientName;
  final int projectId;
  final String projectName;
  final bool isActive;
  final String? updatedAt;

  factory MixerAssignment.fromJson(Map<String, dynamic> json) =>
      MixerAssignment(
        clientId: (json['client_id'] as num).toInt(),
        clientName: '${json['client_name'] ?? ''}',
        projectId: (json['project_id'] as num).toInt(),
        projectName: '${json['project_name'] ?? ''}',
        isActive: json['is_active'] == true || '${json['is_active']}' == '1',
        updatedAt: json['updated_at']?.toString(),
      );
}

class MixerContext {
  const MixerContext({
    required this.id,
    required this.code,
    required this.name,
    required this.activeAssignments,
    required this.assignmentHistory,
  });

  final int id;
  final String code;
  final String name;
  final List<MixerAssignment> activeAssignments;
  final List<MixerAssignment> assignmentHistory;

  MixerAssignment? get assignment =>
      activeAssignments.length == 1 ? activeAssignments.first : null;
  bool get hasAssignmentConflict => activeAssignments.length > 1;
  bool get isOperational => assignment != null;

  factory MixerContext.fromJson(Map<String, dynamic> json) => MixerContext(
        id: (json['id'] as num).toInt(),
        code: '${json['code'] ?? ''}',
        name: '${json['name'] ?? ''}',
        activeAssignments: (json['active_assignments'] as List? ?? const [])
            .map((item) => MixerAssignment.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        assignmentHistory: (json['assignment_history'] as List? ?? const [])
            .map((item) => MixerAssignment.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}
