// Kaneo REST API shapes, ported from `kaneo/apps/mobile/src/lib/api/types.ts`.
//
// Optional fields may be missing or null depending on the server version. Dates stay as the
// strings the server sent; parse them with `lib/core/format/dates.dart`.

int? _int(Object? value) => (value as num?)?.toInt();

num? _num(Object? value) => value as num?;

T? _object<T>(Object? value, T Function(Map<String, dynamic>) fromJson) =>
    value == null ? null : fromJson((value as Map).cast<String, dynamic>());

List<T>? _list<T>(Object? value, T Function(Map<String, dynamic>) fromJson) =>
    (value as List?)?.map((e) => fromJson((e as Map).cast<String, dynamic>())).toList();

const Object _keep = Object();

class InstanceConfig {
  const InstanceConfig({
    this.isCloud,
    this.disableRegistration,
    this.disablePasswordRegistration,
    this.disableEmailOtpSignIn,
    this.disableWorkspaceCreation,
    this.hasSmtp,
    this.hasGithubSignIn,
    this.hasGoogleSignIn,
    this.hasDiscordSignIn,
    this.hasCustomOAuth,
    this.disableLoginForm,
  });

  factory InstanceConfig.fromJson(Map<String, dynamic> json) => InstanceConfig(
    isCloud: json['isCloud'] as bool?,
    disableRegistration: json['disableRegistration'] as bool?,
    disablePasswordRegistration: json['disablePasswordRegistration'] as bool?,
    disableEmailOtpSignIn: json['disableEmailOtpSignIn'] as bool?,
    disableWorkspaceCreation: json['disableWorkspaceCreation'] as bool?,
    hasSmtp: json['hasSmtp'] as bool?,
    hasGithubSignIn: json['hasGithubSignIn'] as bool?,
    hasGoogleSignIn: json['hasGoogleSignIn'] as bool?,
    hasDiscordSignIn: json['hasDiscordSignIn'] as bool?,
    hasCustomOAuth: json['hasCustomOAuth'] as bool?,
    disableLoginForm: json['disableLoginForm'] as bool?,
  );

  final bool? isCloud;
  final bool? disableRegistration;
  final bool? disablePasswordRegistration;
  final bool? disableEmailOtpSignIn;
  final bool? disableWorkspaceCreation;
  final bool? hasSmtp;
  final bool? hasGithubSignIn;
  final bool? hasGoogleSignIn;
  final bool? hasDiscordSignIn;
  final bool? hasCustomOAuth;
  final bool? disableLoginForm;

  Map<String, dynamic> toJson() => {
    if (isCloud != null) 'isCloud': isCloud,
    if (disableRegistration != null) 'disableRegistration': disableRegistration,
    if (disablePasswordRegistration != null)
      'disablePasswordRegistration': disablePasswordRegistration,
    if (disableEmailOtpSignIn != null) 'disableEmailOtpSignIn': disableEmailOtpSignIn,
    if (disableWorkspaceCreation != null) 'disableWorkspaceCreation': disableWorkspaceCreation,
    if (hasSmtp != null) 'hasSmtp': hasSmtp,
    if (hasGithubSignIn != null) 'hasGithubSignIn': hasGithubSignIn,
    if (hasGoogleSignIn != null) 'hasGoogleSignIn': hasGoogleSignIn,
    if (hasDiscordSignIn != null) 'hasDiscordSignIn': hasDiscordSignIn,
    if (hasCustomOAuth != null) 'hasCustomOAuth': hasCustomOAuth,
    if (disableLoginForm != null) 'disableLoginForm': disableLoginForm,
  };
}

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.name,
    required this.email,
    this.image,
    this.role,
  });

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    image: json['image'] as String?,
    role: json['role'] as String?,
  );

  final String id;
  final String name;
  final String email;
  final String? image;
  final String? role;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    if (image != null) 'image': image,
    if (role != null) 'role': role,
  };
}

class AuthTokenUser {
  const AuthTokenUser({required this.id, this.name, this.email});

  factory AuthTokenUser.fromJson(Map<String, dynamic> json) => AuthTokenUser(
    id: json['id'] as String,
    name: json['name'] as String?,
    email: json['email'] as String?,
  );

  final String id;
  final String? name;
  final String? email;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (email != null) 'email': email,
  };
}

class AuthTokenResponse {
  const AuthTokenResponse({this.token, this.user});

  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) => AuthTokenResponse(
    token: json['token'] as String?,
    user: _object(json['user'], AuthTokenUser.fromJson),
  );

  final String? token;
  final AuthTokenUser? user;

  Map<String, dynamic> toJson() => {
    if (token != null) 'token': token,
    if (user != null) 'user': user!.toJson(),
  };
}

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.slug,
    this.logo,
    this.createdAt,
    this.role,
    this.description,
    this.metadata,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    logo: json['logo'] as String?,
    createdAt: json['createdAt'] as String?,
    role: json['role'] as String?,
    description: json['description'] as String?,
    metadata: json['metadata'],
  );

  final String id;
  final String name;
  final String slug;
  final String? logo;
  final String? createdAt;
  final String? role;
  final String? description;
  final Object? metadata;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    if (logo != null) 'logo': logo,
    if (createdAt != null) 'createdAt': createdAt,
    if (role != null) 'role': role,
    if (description != null) 'description': description,
    if (metadata != null) 'metadata': metadata,
  };
}

class WorkspaceMember {
  const WorkspaceMember({
    required this.id,
    required this.name,
    required this.email,
    this.image,
    required this.role,
  });

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) => WorkspaceMember(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    image: json['image'] as String?,
    role: json['role'] as String,
  );

  final String id;
  final String name;
  final String email;
  final String? image;
  final String role;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    if (image != null) 'image': image,
    'role': role,
  };
}

class OrganizationInvitation {
  const OrganizationInvitation({
    required this.id,
    required this.email,
    this.role,
    required this.status,
    this.expiresAt,
  });

  factory OrganizationInvitation.fromJson(Map<String, dynamic> json) => OrganizationInvitation(
    id: json['id'] as String,
    email: json['email'] as String,
    role: json['role'] as String?,
    status: json['status'] as String,
    expiresAt: json['expiresAt'] as String?,
  );

  final String id;
  final String email;
  final String? role;
  final String status;
  final String? expiresAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    if (role != null) 'role': role,
    'status': status,
    if (expiresAt != null) 'expiresAt': expiresAt,
  };
}

class OrganizationMemberUser {
  const OrganizationMemberUser({this.id, this.name, this.email, this.image});

  factory OrganizationMemberUser.fromJson(Map<String, dynamic> json) => OrganizationMemberUser(
    id: json['id'] as String?,
    name: json['name'] as String?,
    email: json['email'] as String?,
    image: json['image'] as String?,
  );

  final String? id;
  final String? name;
  final String? email;
  final String? image;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (name != null) 'name': name,
    if (email != null) 'email': email,
    if (image != null) 'image': image,
  };
}

class OrganizationMember {
  const OrganizationMember({required this.id, required this.userId, required this.role, this.user});

  factory OrganizationMember.fromJson(Map<String, dynamic> json) => OrganizationMember(
    id: json['id'] as String,
    userId: json['userId'] as String,
    role: json['role'] as String,
    user: _object(json['user'], OrganizationMemberUser.fromJson),
  );

  final String id;
  final String userId;
  final String role;
  final OrganizationMemberUser? user;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'role': role,
    if (user != null) 'user': user!.toJson(),
  };
}

class FullOrganization {
  const FullOrganization({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.metadata,
    this.members,
    this.invitations,
  });

  factory FullOrganization.fromJson(Map<String, dynamic> json) => FullOrganization(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    description: json['description'] as String?,
    metadata: json['metadata'],
    members: _list(json['members'], OrganizationMember.fromJson),
    invitations: _list(json['invitations'], OrganizationInvitation.fromJson),
  );

  final String id;
  final String name;
  final String slug;
  final String? description;
  final Object? metadata;
  final List<OrganizationMember>? members;
  final List<OrganizationInvitation>? invitations;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    if (description != null) 'description': description,
    if (metadata != null) 'metadata': metadata,
    if (members != null) 'members': members!.map((e) => e.toJson()).toList(),
    if (invitations != null) 'invitations': invitations!.map((e) => e.toJson()).toList(),
  };
}

class PendingInvitation {
  const PendingInvitation({
    required this.id,
    required this.email,
    required this.workspaceId,
    required this.workspaceName,
    required this.inviterName,
    this.expiresAt,
    this.createdAt,
    required this.status,
  });

  factory PendingInvitation.fromJson(Map<String, dynamic> json) => PendingInvitation(
    id: json['id'] as String,
    email: json['email'] as String,
    workspaceId: json['workspaceId'] as String,
    workspaceName: json['workspaceName'] as String,
    inviterName: json['inviterName'] as String,
    expiresAt: json['expiresAt'] as String?,
    createdAt: json['createdAt'] as String?,
    status: json['status'] as String,
  );

  final String id;
  final String email;
  final String workspaceId;
  final String workspaceName;
  final String inviterName;
  final String? expiresAt;
  final String? createdAt;
  final String status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'workspaceId': workspaceId,
    'workspaceName': workspaceName,
    'inviterName': inviterName,
    if (expiresAt != null) 'expiresAt': expiresAt,
    if (createdAt != null) 'createdAt': createdAt,
    'status': status,
  };
}

class ProjectStatistics {
  const ProjectStatistics({this.completionPercentage, this.totalTasks, this.dueDate});

  factory ProjectStatistics.fromJson(Map<String, dynamic> json) => ProjectStatistics(
    completionPercentage: _num(json['completionPercentage']),
    totalTasks: _num(json['totalTasks']),
    dueDate: json['dueDate'] as String?,
  );

  final num? completionPercentage;
  final num? totalTasks;
  final String? dueDate;

  Map<String, dynamic> toJson() => {
    if (completionPercentage != null) 'completionPercentage': completionPercentage,
    if (totalTasks != null) 'totalTasks': totalTasks,
    if (dueDate != null) 'dueDate': dueDate,
  };
}

class Project {
  const Project({
    required this.id,
    required this.workspaceId,
    required this.slug,
    this.icon,
    required this.name,
    this.description,
    this.createdAt,
    this.isPublic,
    this.archivedAt,
    this.position,
    this.statistics,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    workspaceId: json['workspaceId'] as String,
    slug: json['slug'] as String,
    icon: json['icon'] as String?,
    name: json['name'] as String,
    description: json['description'] as String?,
    createdAt: json['createdAt'] as String?,
    isPublic: json['isPublic'] as bool?,
    archivedAt: json['archivedAt'] as String?,
    position: _num(json['position']),
    statistics: _object(json['statistics'], ProjectStatistics.fromJson),
  );

  final String id;
  final String workspaceId;
  final String slug;
  final String? icon;
  final String name;
  final String? description;
  final String? createdAt;
  final bool? isPublic;
  final String? archivedAt;
  final num? position;
  final ProjectStatistics? statistics;

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'slug': slug,
    if (icon != null) 'icon': icon,
    'name': name,
    if (description != null) 'description': description,
    if (createdAt != null) 'createdAt': createdAt,
    if (isPublic != null) 'isPublic': isPublic,
    if (archivedAt != null) 'archivedAt': archivedAt,
    if (position != null) 'position': position,
    if (statistics != null) 'statistics': statistics!.toJson(),
  };

  /// Pass null to clear an optional field; leave it out to keep the value.
  Project copyWith({
    String? id,
    String? workspaceId,
    String? slug,
    Object? icon = _keep,
    String? name,
    Object? description = _keep,
    Object? createdAt = _keep,
    Object? isPublic = _keep,
    Object? archivedAt = _keep,
    Object? position = _keep,
    Object? statistics = _keep,
  }) => Project(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    slug: slug ?? this.slug,
    icon: identical(icon, _keep) ? this.icon : icon as String?,
    name: name ?? this.name,
    description: identical(description, _keep) ? this.description : description as String?,
    createdAt: identical(createdAt, _keep) ? this.createdAt : createdAt as String?,
    isPublic: identical(isPublic, _keep) ? this.isPublic : isPublic as bool?,
    archivedAt: identical(archivedAt, _keep) ? this.archivedAt : archivedAt as String?,
    position: identical(position, _keep) ? this.position : position as num?,
    statistics: identical(statistics, _keep) ? this.statistics : statistics as ProjectStatistics?,
  );
}

class TaskLabel {
  const TaskLabel({required this.id, required this.name, required this.color});

  factory TaskLabel.fromJson(Map<String, dynamic> json) => TaskLabel(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
  );

  final String id;
  final String name;
  final String color;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
}

class SubtaskCounts {
  const SubtaskCounts({this.completed, this.total});

  factory SubtaskCounts.fromJson(Map<String, dynamic> json) =>
      SubtaskCounts(completed: _num(json['completed']), total: _num(json['total']));

  final num? completed;
  final num? total;

  Map<String, dynamic> toJson() => {
    if (completed != null) 'completed': completed,
    if (total != null) 'total': total,
  };
}

class BoardTask {
  const BoardTask({
    required this.id,
    required this.title,
    this.number,
    this.description,
    required this.status,
    this.priority,
    this.startDate,
    this.dueDate,
    this.position,
    this.createdAt,
    this.userId,
    this.assigneeName,
    this.assigneeId,
    this.assigneeImage,
    required this.projectId,
    this.subtaskCounts,
    this.labels,
  });

  factory BoardTask.fromJson(Map<String, dynamic> json) => BoardTask(
    id: json['id'] as String,
    title: json['title'] as String,
    number: _int(json['number']),
    description: json['description'] as String?,
    status: json['status'] as String,
    priority: json['priority'] as String?,
    startDate: json['startDate'] as String?,
    dueDate: json['dueDate'] as String?,
    position: _num(json['position']),
    createdAt: json['createdAt'] as String?,
    userId: json['userId'] as String?,
    assigneeName: json['assigneeName'] as String?,
    assigneeId: json['assigneeId'] as String?,
    assigneeImage: json['assigneeImage'] as String?,
    projectId: json['projectId'] as String,
    subtaskCounts: _object(json['subtaskCounts'], SubtaskCounts.fromJson),
    labels: _list(json['labels'], TaskLabel.fromJson),
  );

  final String id;
  final String title;
  final int? number;
  final String? description;
  final String status;
  final String? priority;
  final String? startDate;
  final String? dueDate;
  final num? position;
  final String? createdAt;
  final String? userId;
  final String? assigneeName;
  final String? assigneeId;
  final String? assigneeImage;
  final String projectId;
  final SubtaskCounts? subtaskCounts;
  final List<TaskLabel>? labels;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (number != null) 'number': number,
    if (description != null) 'description': description,
    'status': status,
    if (priority != null) 'priority': priority,
    if (startDate != null) 'startDate': startDate,
    if (dueDate != null) 'dueDate': dueDate,
    if (position != null) 'position': position,
    if (createdAt != null) 'createdAt': createdAt,
    if (userId != null) 'userId': userId,
    if (assigneeName != null) 'assigneeName': assigneeName,
    if (assigneeId != null) 'assigneeId': assigneeId,
    if (assigneeImage != null) 'assigneeImage': assigneeImage,
    'projectId': projectId,
    if (subtaskCounts != null) 'subtaskCounts': subtaskCounts!.toJson(),
    if (labels != null) 'labels': labels!.map((e) => e.toJson()).toList(),
  };

  /// Pass null to clear an optional field; leave it out to keep the value.
  BoardTask copyWith({
    String? id,
    String? title,
    Object? number = _keep,
    Object? description = _keep,
    String? status,
    Object? priority = _keep,
    Object? startDate = _keep,
    Object? dueDate = _keep,
    Object? position = _keep,
    Object? createdAt = _keep,
    Object? userId = _keep,
    Object? assigneeName = _keep,
    Object? assigneeId = _keep,
    Object? assigneeImage = _keep,
    String? projectId,
    Object? subtaskCounts = _keep,
    Object? labels = _keep,
  }) => BoardTask(
    id: id ?? this.id,
    title: title ?? this.title,
    number: identical(number, _keep) ? this.number : number as int?,
    description: identical(description, _keep) ? this.description : description as String?,
    status: status ?? this.status,
    priority: identical(priority, _keep) ? this.priority : priority as String?,
    startDate: identical(startDate, _keep) ? this.startDate : startDate as String?,
    dueDate: identical(dueDate, _keep) ? this.dueDate : dueDate as String?,
    position: identical(position, _keep) ? this.position : position as num?,
    createdAt: identical(createdAt, _keep) ? this.createdAt : createdAt as String?,
    userId: identical(userId, _keep) ? this.userId : userId as String?,
    assigneeName: identical(assigneeName, _keep) ? this.assigneeName : assigneeName as String?,
    assigneeId: identical(assigneeId, _keep) ? this.assigneeId : assigneeId as String?,
    assigneeImage: identical(assigneeImage, _keep) ? this.assigneeImage : assigneeImage as String?,
    projectId: projectId ?? this.projectId,
    subtaskCounts: identical(subtaskCounts, _keep)
        ? this.subtaskCounts
        : subtaskCounts as SubtaskCounts?,
    labels: identical(labels, _keep) ? this.labels : labels as List<TaskLabel>?,
  );
}

class BoardColumn {
  const BoardColumn({
    required this.id,
    required this.slug,
    required this.name,
    this.icon,
    this.isFinal,
    this.position,
    this.tasks,
  });

  factory BoardColumn.fromJson(Map<String, dynamic> json) => BoardColumn(
    id: json['id'] as String,
    slug: json['slug'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String?,
    isFinal: json['isFinal'] as bool?,
    position: _num(json['position']),
    tasks: _list(json['tasks'], BoardTask.fromJson),
  );

  final String id;
  final String slug;
  final String name;
  final String? icon;
  final bool? isFinal;
  final num? position;
  final List<BoardTask>? tasks;

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'name': name,
    if (icon != null) 'icon': icon,
    if (isFinal != null) 'isFinal': isFinal,
    if (position != null) 'position': position,
    if (tasks != null) 'tasks': tasks!.map((e) => e.toJson()).toList(),
  };

  /// Pass null to clear an optional field; leave it out to keep the value.
  BoardColumn copyWith({
    String? id,
    String? slug,
    String? name,
    Object? icon = _keep,
    Object? isFinal = _keep,
    Object? position = _keep,
    Object? tasks = _keep,
  }) => BoardColumn(
    id: id ?? this.id,
    slug: slug ?? this.slug,
    name: name ?? this.name,
    icon: identical(icon, _keep) ? this.icon : icon as String?,
    isFinal: identical(isFinal, _keep) ? this.isFinal : isFinal as bool?,
    position: identical(position, _keep) ? this.position : position as num?,
    tasks: identical(tasks, _keep) ? this.tasks : tasks as List<BoardTask>?,
  );
}

class BoardData {
  const BoardData({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.isPublic,
    required this.workspaceId,
    required this.columns,
    required this.archivedTasks,
    required this.plannedTasks,
  });

  factory BoardData.fromJson(Map<String, dynamic> json) => BoardData(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    icon: json['icon'] as String?,
    isPublic: json['isPublic'] as bool?,
    workspaceId: json['workspaceId'] as String,
    columns: _list(json['columns'], BoardColumn.fromJson) ?? const [],
    archivedTasks: _list(json['archivedTasks'], BoardTask.fromJson) ?? const [],
    plannedTasks: _list(json['plannedTasks'], BoardTask.fromJson) ?? const [],
  );

  final String id;
  final String name;
  final String slug;
  final String? icon;
  final bool? isPublic;
  final String workspaceId;
  final List<BoardColumn> columns;
  final List<BoardTask> archivedTasks;
  final List<BoardTask> plannedTasks;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    if (icon != null) 'icon': icon,
    if (isPublic != null) 'isPublic': isPublic,
    'workspaceId': workspaceId,
    'columns': columns.map((e) => e.toJson()).toList(),
    'archivedTasks': archivedTasks.map((e) => e.toJson()).toList(),
    'plannedTasks': plannedTasks.map((e) => e.toJson()).toList(),
  };

  /// Pass null to clear an optional field; leave it out to keep the value.
  BoardData copyWith({
    String? id,
    String? name,
    String? slug,
    Object? icon = _keep,
    Object? isPublic = _keep,
    String? workspaceId,
    List<BoardColumn>? columns,
    List<BoardTask>? archivedTasks,
    List<BoardTask>? plannedTasks,
  }) => BoardData(
    id: id ?? this.id,
    name: name ?? this.name,
    slug: slug ?? this.slug,
    icon: identical(icon, _keep) ? this.icon : icon as String?,
    isPublic: identical(isPublic, _keep) ? this.isPublic : isPublic as bool?,
    workspaceId: workspaceId ?? this.workspaceId,
    columns: columns ?? this.columns,
    archivedTasks: archivedTasks ?? this.archivedTasks,
    plannedTasks: plannedTasks ?? this.plannedTasks,
  );
}

class BoardPagination {
  const BoardPagination({
    this.total,
    this.page,
    this.totalPages,
    this.relatedPage,
    this.relatedTotalPages,
  });

  factory BoardPagination.fromJson(Map<String, dynamic> json) => BoardPagination(
    total: _int(json['total']),
    page: _int(json['page']),
    totalPages: _int(json['totalPages']),
    relatedPage: _int(json['relatedPage']),
    relatedTotalPages: _int(json['relatedTotalPages']),
  );

  final int? total;
  final int? page;
  final int? totalPages;
  final int? relatedPage;
  final int? relatedTotalPages;

  Map<String, dynamic> toJson() => {
    if (total != null) 'total': total,
    if (page != null) 'page': page,
    if (totalPages != null) 'totalPages': totalPages,
    if (relatedPage != null) 'relatedPage': relatedPage,
    if (relatedTotalPages != null) 'relatedTotalPages': relatedTotalPages,
  };
}

class BoardResponse {
  const BoardResponse({required this.data, this.pagination});

  factory BoardResponse.fromJson(Map<String, dynamic> json) => BoardResponse(
    data: _object(json['data'], BoardData.fromJson)!,
    pagination: _object(json['pagination'], BoardPagination.fromJson),
  );

  final BoardData data;
  final BoardPagination? pagination;

  Map<String, dynamic> toJson() => {
    'data': data.toJson(),
    if (pagination != null) 'pagination': pagination!.toJson(),
  };
}

class Task {
  const Task({
    required this.id,
    required this.projectId,
    this.position,
    this.number,
    this.userId,
    required this.title,
    this.description,
    this.descriptionDeferred,
    required this.status,
    this.priority,
    this.startDate,
    this.dueDate,
    this.createdAt,
    this.workspaceId,
    this.columnId,
    this.assigneeName,
    this.assigneeId,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    position: _num(json['position']),
    number: _int(json['number']),
    userId: json['userId'] as String?,
    title: json['title'] as String,
    description: json['description'] as String?,
    descriptionDeferred: json['descriptionDeferred'] as bool?,
    status: json['status'] as String,
    priority: json['priority'] as String?,
    startDate: json['startDate'] as String?,
    dueDate: json['dueDate'] as String?,
    createdAt: json['createdAt'] as String?,
    workspaceId: json['workspaceId'] as String?,
    columnId: json['columnId'] as String?,
    assigneeName: json['assigneeName'] as String?,
    assigneeId: json['assigneeId'] as String?,
  );

  final String id;
  final String projectId;
  final num? position;
  final int? number;
  final String? userId;
  final String title;
  final String? description;
  final bool? descriptionDeferred;
  final String status;
  final String? priority;
  final String? startDate;
  final String? dueDate;
  final String? createdAt;
  final String? workspaceId;
  final String? columnId;
  final String? assigneeName;
  final String? assigneeId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    if (position != null) 'position': position,
    if (number != null) 'number': number,
    if (userId != null) 'userId': userId,
    'title': title,
    if (description != null) 'description': description,
    if (descriptionDeferred != null) 'descriptionDeferred': descriptionDeferred,
    'status': status,
    if (priority != null) 'priority': priority,
    if (startDate != null) 'startDate': startDate,
    if (dueDate != null) 'dueDate': dueDate,
    if (createdAt != null) 'createdAt': createdAt,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (columnId != null) 'columnId': columnId,
    if (assigneeName != null) 'assigneeName': assigneeName,
    if (assigneeId != null) 'assigneeId': assigneeId,
  };

  /// Pass null to clear an optional field; leave it out to keep the value.
  Task copyWith({
    String? id,
    String? projectId,
    Object? position = _keep,
    Object? number = _keep,
    Object? userId = _keep,
    String? title,
    Object? description = _keep,
    Object? descriptionDeferred = _keep,
    String? status,
    Object? priority = _keep,
    Object? startDate = _keep,
    Object? dueDate = _keep,
    Object? createdAt = _keep,
    Object? workspaceId = _keep,
    Object? columnId = _keep,
    Object? assigneeName = _keep,
    Object? assigneeId = _keep,
  }) => Task(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    position: identical(position, _keep) ? this.position : position as num?,
    number: identical(number, _keep) ? this.number : number as int?,
    userId: identical(userId, _keep) ? this.userId : userId as String?,
    title: title ?? this.title,
    description: identical(description, _keep) ? this.description : description as String?,
    descriptionDeferred: identical(descriptionDeferred, _keep)
        ? this.descriptionDeferred
        : descriptionDeferred as bool?,
    status: status ?? this.status,
    priority: identical(priority, _keep) ? this.priority : priority as String?,
    startDate: identical(startDate, _keep) ? this.startDate : startDate as String?,
    dueDate: identical(dueDate, _keep) ? this.dueDate : dueDate as String?,
    createdAt: identical(createdAt, _keep) ? this.createdAt : createdAt as String?,
    workspaceId: identical(workspaceId, _keep) ? this.workspaceId : workspaceId as String?,
    columnId: identical(columnId, _keep) ? this.columnId : columnId as String?,
    assigneeName: identical(assigneeName, _keep) ? this.assigneeName : assigneeName as String?,
    assigneeId: identical(assigneeId, _keep) ? this.assigneeId : assigneeId as String?,
  );
}

/// The subtask progress of a task's parent, read along with the task for a board.
class ParentSubtaskCounts {
  const ParentSubtaskCounts({required this.taskId, required this.counts});

  factory ParentSubtaskCounts.fromJson(Map<String, dynamic> json) =>
      ParentSubtaskCounts(taskId: json['taskId'] as String, counts: SubtaskCounts.fromJson(json));

  final String taskId;
  final SubtaskCounts counts;
}

/// One task as a board shows it, without reading the board. The progress of its parents comes along,
/// because that is what a change of status changes elsewhere on the board.
class TaskForBoard {
  const TaskForBoard({required this.task, this.subtaskCounts, this.parentSubtaskCounts = const []});

  factory TaskForBoard.fromJson(Map<String, dynamic> json) => TaskForBoard(
    task: Task.fromJson(json),
    subtaskCounts: _object(json['subtaskCounts'], SubtaskCounts.fromJson),
    parentSubtaskCounts:
        _list(json['parentSubtaskCounts'], ParentSubtaskCounts.fromJson) ??
        const <ParentSubtaskCounts>[],
  );

  final Task task;
  final SubtaskCounts? subtaskCounts;
  final List<ParentSubtaskCounts> parentSubtaskCounts;
}

class DescriptionPage {
  const DescriptionPage({required this.content, required this.version, this.nextOffset});

  factory DescriptionPage.fromJson(Map<String, dynamic> json) => DescriptionPage(
    content: json['content'] as String,
    version: json['version'] as String,
    nextOffset: _int(json['nextOffset']),
  );

  final String content;
  final String version;
  final int? nextOffset;

  Map<String, dynamic> toJson() => {
    'content': content,
    'version': version,
    if (nextOffset != null) 'nextOffset': nextOffset,
  };
}

class AssignedTask {
  const AssignedTask({
    required this.id,
    required this.projectId,
    this.number,
    required this.title,
    required this.status,
    this.statusName,
    this.statusIcon,
    this.priority,
    this.dueDate,
    required this.projectName,
    this.projectIcon,
    required this.projectSlug,
    this.labels,
  });

  factory AssignedTask.fromJson(Map<String, dynamic> json) => AssignedTask(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    number: _int(json['number']),
    title: json['title'] as String,
    status: json['status'] as String,
    statusName: json['statusName'] as String?,
    statusIcon: json['statusIcon'] as String?,
    priority: json['priority'] as String?,
    dueDate: json['dueDate'] as String?,
    projectName: json['projectName'] as String,
    projectIcon: json['projectIcon'] as String?,
    projectSlug: json['projectSlug'] as String,
    labels: _list(json['labels'], TaskLabel.fromJson),
  );

  final String id;
  final String projectId;
  final int? number;
  final String title;
  final String status;
  final String? statusName;
  final String? statusIcon;
  final String? priority;
  final String? dueDate;
  final String projectName;
  final String? projectIcon;
  final String projectSlug;
  final List<TaskLabel>? labels;

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    if (number != null) 'number': number,
    'title': title,
    'status': status,
    if (statusName != null) 'statusName': statusName,
    if (statusIcon != null) 'statusIcon': statusIcon,
    if (priority != null) 'priority': priority,
    if (dueDate != null) 'dueDate': dueDate,
    'projectName': projectName,
    if (projectIcon != null) 'projectIcon': projectIcon,
    'projectSlug': projectSlug,
    if (labels != null) 'labels': labels!.map((e) => e.toJson()).toList(),
  };
}

class AssignedTasks {
  const AssignedTasks({required this.tasks, this.total});

  factory AssignedTasks.fromJson(Map<String, dynamic> json) => AssignedTasks(
    tasks: _list(json['tasks'], AssignedTask.fromJson) ?? const [],
    total: _int(json['total']),
  );

  final List<AssignedTask> tasks;
  final int? total;

  Map<String, dynamic> toJson() => {
    'tasks': tasks.map((e) => e.toJson()).toList(),
    if (total != null) 'total': total,
  };
}

class ProjectColumn {
  const ProjectColumn({
    required this.id,
    required this.projectId,
    required this.name,
    required this.slug,
    this.position,
    this.icon,
    this.color,
    this.isFinal,
  });

  factory ProjectColumn.fromJson(Map<String, dynamic> json) => ProjectColumn(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    position: _num(json['position']),
    icon: json['icon'] as String?,
    color: json['color'] as String?,
    isFinal: json['isFinal'] as bool?,
  );

  final String id;
  final String projectId;
  final String name;
  final String slug;
  final num? position;
  final String? icon;
  final String? color;
  final bool? isFinal;

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'name': name,
    'slug': slug,
    if (position != null) 'position': position,
    if (icon != null) 'icon': icon,
    if (color != null) 'color': color,
    if (isFinal != null) 'isFinal': isFinal,
  };
}

class Activity {
  const Activity({
    required this.id,
    required this.taskId,
    required this.type,
    required this.createdAt,
    this.updatedAt,
    this.userId,
    this.content,
    this.eventData,
    this.externalUserName,
    this.externalSource,
  });

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: json['id'] as String,
    taskId: json['taskId'] as String,
    type: json['type'] as String,
    createdAt: json['createdAt'] as String,
    updatedAt: json['updatedAt'] as String?,
    userId: json['userId'] as String?,
    content: json['content'] as String?,
    eventData: json['eventData'],
    externalUserName: json['externalUserName'] as String?,
    externalSource: json['externalSource'] as String?,
  );

  final String id;
  final String taskId;
  final String type;
  final String createdAt;
  final String? updatedAt;
  final String? userId;
  final String? content;
  final Object? eventData;
  final String? externalUserName;
  final String? externalSource;

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'type': type,
    'createdAt': createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
    if (userId != null) 'userId': userId,
    if (content != null) 'content': content,
    if (eventData != null) 'eventData': eventData,
    if (externalUserName != null) 'externalUserName': externalUserName,
    if (externalSource != null) 'externalSource': externalSource,
  };
}

class WorkspaceActivity {
  const WorkspaceActivity({
    required this.id,
    required this.type,
    required this.createdAt,
    this.eventData,
    this.excerpt,
    this.userId,
    this.userName,
    this.userImage,
    this.externalUserName,
    required this.taskId,
    required this.taskTitle,
    this.taskNumber,
    required this.projectId,
    required this.projectSlug,
  });

  factory WorkspaceActivity.fromJson(Map<String, dynamic> json) => WorkspaceActivity(
    id: json['id'] as String,
    type: json['type'] as String,
    createdAt: json['createdAt'] as String,
    eventData: json['eventData'],
    excerpt: json['excerpt'] as String?,
    userId: json['userId'] as String?,
    userName: json['userName'] as String?,
    userImage: json['userImage'] as String?,
    externalUserName: json['externalUserName'] as String?,
    taskId: json['taskId'] as String,
    taskTitle: json['taskTitle'] as String,
    taskNumber: _int(json['taskNumber']),
    projectId: json['projectId'] as String,
    projectSlug: json['projectSlug'] as String,
  );

  final String id;
  final String type;
  final String createdAt;
  final Object? eventData;
  final String? excerpt;
  final String? userId;
  final String? userName;
  final String? userImage;
  final String? externalUserName;
  final String taskId;
  final String taskTitle;
  final int? taskNumber;
  final String projectId;
  final String projectSlug;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'createdAt': createdAt,
    if (eventData != null) 'eventData': eventData,
    if (excerpt != null) 'excerpt': excerpt,
    if (userId != null) 'userId': userId,
    if (userName != null) 'userName': userName,
    if (userImage != null) 'userImage': userImage,
    if (externalUserName != null) 'externalUserName': externalUserName,
    'taskId': taskId,
    'taskTitle': taskTitle,
    if (taskNumber != null) 'taskNumber': taskNumber,
    'projectId': projectId,
    'projectSlug': projectSlug,
  };
}

class Label {
  const Label({
    required this.id,
    required this.name,
    required this.color,
    this.taskId,
    this.workspaceId,
    this.deletionStartedAt,
  });

  factory Label.fromJson(Map<String, dynamic> json) => Label(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    taskId: json['taskId'] as String?,
    workspaceId: json['workspaceId'] as String?,
    deletionStartedAt: json['deletionStartedAt'] as String?,
  );

  final String id;
  final String name;
  final String color;
  final String? taskId;
  final String? workspaceId;
  final String? deletionStartedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    if (taskId != null) 'taskId': taskId,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (deletionStartedAt != null) 'deletionStartedAt': deletionStartedAt,
  };
}

class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.taskId,
    this.userId,
    this.userName,
    required this.startTime,
    this.endTime,
    this.duration,
    this.description,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> json) => TimeEntry(
    id: json['id'] as String,
    taskId: json['taskId'] as String,
    userId: json['userId'] as String?,
    userName: json['userName'] as String?,
    startTime: json['startTime'] as String,
    endTime: json['endTime'] as String?,
    duration: _num(json['duration']),
    description: json['description'] as String?,
  );

  final String id;
  final String taskId;
  final String? userId;
  final String? userName;
  final String startTime;
  final String? endTime;
  final num? duration;
  final String? description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    if (userId != null) 'userId': userId,
    if (userName != null) 'userName': userName,
    'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    if (duration != null) 'duration': duration,
    if (description != null) 'description': description,
  };
}

class RelatedTask {
  const RelatedTask({
    required this.id,
    required this.title,
    required this.status,
    this.isCompleted,
    this.priority,
    this.number,
    required this.projectId,
    this.assigneeName,
  });

  factory RelatedTask.fromJson(Map<String, dynamic> json) => RelatedTask(
    id: json['id'] as String,
    title: json['title'] as String,
    status: json['status'] as String,
    isCompleted: json['isCompleted'] as bool?,
    priority: json['priority'] as String?,
    number: _int(json['number']),
    projectId: json['projectId'] as String,
    assigneeName: json['assigneeName'] as String?,
  );

  final String id;
  final String title;
  final String status;
  final bool? isCompleted;
  final String? priority;
  final int? number;
  final String projectId;
  final String? assigneeName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status,
    if (isCompleted != null) 'isCompleted': isCompleted,
    if (priority != null) 'priority': priority,
    if (number != null) 'number': number,
    'projectId': projectId,
    if (assigneeName != null) 'assigneeName': assigneeName,
  };
}

/// `sourceTask` and `targetTask` are only filled by the per-task endpoint, not the project one.
class TaskRelation {
  const TaskRelation({
    required this.id,
    required this.sourceTaskId,
    required this.targetTaskId,
    required this.relationType,
    this.createdAt,
    this.sourceTask,
    this.targetTask,
  });

  factory TaskRelation.fromJson(Map<String, dynamic> json) => TaskRelation(
    id: json['id'] as String,
    sourceTaskId: json['sourceTaskId'] as String,
    targetTaskId: json['targetTaskId'] as String,
    relationType: json['relationType'] as String,
    createdAt: json['createdAt'] as String?,
    sourceTask: _object(json['sourceTask'], RelatedTask.fromJson),
    targetTask: _object(json['targetTask'], RelatedTask.fromJson),
  );

  final String id;
  final String sourceTaskId;
  final String targetTaskId;
  final String relationType;
  final String? createdAt;
  final RelatedTask? sourceTask;
  final RelatedTask? targetTask;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceTaskId': sourceTaskId,
    'targetTaskId': targetTaskId,
    'relationType': relationType,
    if (createdAt != null) 'createdAt': createdAt,
    if (sourceTask != null) 'sourceTask': sourceTask!.toJson(),
    if (targetTask != null) 'targetTask': targetTask!.toJson(),
  };
}

class ExternalLink {
  const ExternalLink({
    required this.id,
    required this.taskId,
    this.integrationId,
    required this.resourceType,
    required this.externalId,
    required this.url,
    this.title,
  });

  factory ExternalLink.fromJson(Map<String, dynamic> json) => ExternalLink(
    id: json['id'] as String,
    taskId: json['taskId'] as String,
    integrationId: json['integrationId'] as String?,
    resourceType: json['resourceType'] as String,
    externalId: json['externalId'] as String,
    url: json['url'] as String,
    title: json['title'] as String?,
  );

  final String id;
  final String taskId;
  final String? integrationId;
  final String resourceType;
  final String externalId;
  final String url;
  final String? title;

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    if (integrationId != null) 'integrationId': integrationId,
    'resourceType': resourceType,
    'externalId': externalId,
    'url': url,
    if (title != null) 'title': title,
  };
}

class CustomFieldDefinition {
  const CustomFieldDefinition({
    required this.id,
    required this.projectId,
    required this.name,
    required this.type,
    this.required,
    this.defaultValue,
    this.options,
    this.position,
  });

  factory CustomFieldDefinition.fromJson(Map<String, dynamic> json) => CustomFieldDefinition(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    required: json['required'] as bool?,
    defaultValue: json['defaultValue'] as String?,
    options: json['options'],
    position: _int(json['position']),
  );

  final String id;
  final String projectId;
  final String name;
  final String type;
  final bool? required;
  final String? defaultValue;
  final Object? options;
  final int? position;

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'name': name,
    'type': type,
    if (required != null) 'required': required,
    if (defaultValue != null) 'defaultValue': defaultValue,
    if (options != null) 'options': options,
    if (position != null) 'position': position,
  };
}

class CustomFieldValue {
  const CustomFieldValue({
    required this.id,
    required this.taskId,
    required this.fieldId,
    this.value,
    required this.fieldName,
    required this.fieldType,
  });

  factory CustomFieldValue.fromJson(Map<String, dynamic> json) => CustomFieldValue(
    id: json['id'] as String,
    taskId: json['taskId'] as String,
    fieldId: json['fieldId'] as String,
    value: json['value'] as String?,
    fieldName: json['fieldName'] as String,
    fieldType: json['fieldType'] as String,
  );

  final String id;
  final String taskId;
  final String fieldId;
  final String? value;
  final String fieldName;
  final String fieldType;

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'fieldId': fieldId,
    if (value != null) 'value': value,
    'fieldName': fieldName,
    'fieldType': fieldType,
  };
}

class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.userId,
    this.title,
    this.content,
    required this.type,
    this.eventData,
    this.isRead,
    this.resourceId,
    this.resourceType,
    required this.createdAt,
  });

  factory InboxNotification.fromJson(Map<String, dynamic> json) => InboxNotification(
    id: json['id'] as String,
    userId: json['userId'] as String,
    title: json['title'] as String?,
    content: json['content'] as String?,
    type: json['type'] as String,
    eventData: json['eventData'],
    isRead: json['isRead'] as bool?,
    resourceId: json['resourceId'] as String?,
    resourceType: json['resourceType'] as String?,
    createdAt: json['createdAt'] as String,
  );

  final String id;
  final String userId;
  final String? title;
  final String? content;
  final String type;
  final Object? eventData;
  final bool? isRead;
  final String? resourceId;
  final String? resourceType;
  final String createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    if (title != null) 'title': title,
    if (content != null) 'content': content,
    'type': type,
    if (eventData != null) 'eventData': eventData,
    if (isRead != null) 'isRead': isRead,
    if (resourceId != null) 'resourceId': resourceId,
    if (resourceType != null) 'resourceType': resourceType,
    'createdAt': createdAt,
  };

  /// Pass null to clear an optional field; leave it out to keep the value.
  InboxNotification copyWith({
    String? id,
    String? userId,
    Object? title = _keep,
    Object? content = _keep,
    String? type,
    Object? eventData = _keep,
    Object? isRead = _keep,
    Object? resourceId = _keep,
    Object? resourceType = _keep,
    String? createdAt,
  }) => InboxNotification(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: identical(title, _keep) ? this.title : title as String?,
    content: identical(content, _keep) ? this.content : content as String?,
    type: type ?? this.type,
    eventData: identical(eventData, _keep) ? this.eventData : eventData,
    isRead: identical(isRead, _keep) ? this.isRead : isRead as bool?,
    resourceId: identical(resourceId, _keep) ? this.resourceId : resourceId as String?,
    resourceType: identical(resourceType, _keep) ? this.resourceType : resourceType as String?,
    createdAt: createdAt ?? this.createdAt,
  );
}

class NotificationPreferences {
  const NotificationPreferences({
    this.emailAddress,
    this.emailEnabled,
    this.ntfyEnabled,
    this.ntfyServerUrl,
    this.ntfyTopic,
    this.ntfyTokenConfigured,
    this.gotifyEnabled,
    this.gotifyServerUrl,
    this.gotifyTokenConfigured,
    this.webhookEnabled,
    this.webhookUrl,
    this.webhookSecretConfigured,
    this.taskAssignmentEnabled,
    this.taskCommentEnabled,
    this.taskStatusChangeEnabled,
    this.dueDateReminderEnabled,
    this.dueDateReminderLeadTimeMinutes,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) => NotificationPreferences(
    emailAddress: json['emailAddress'] as String?,
    emailEnabled: json['emailEnabled'] as bool?,
    ntfyEnabled: json['ntfyEnabled'] as bool?,
    ntfyServerUrl: json['ntfyServerUrl'] as String?,
    ntfyTopic: json['ntfyTopic'] as String?,
    ntfyTokenConfigured: json['ntfyTokenConfigured'] as bool?,
    gotifyEnabled: json['gotifyEnabled'] as bool?,
    gotifyServerUrl: json['gotifyServerUrl'] as String?,
    gotifyTokenConfigured: json['gotifyTokenConfigured'] as bool?,
    webhookEnabled: json['webhookEnabled'] as bool?,
    webhookUrl: json['webhookUrl'] as String?,
    webhookSecretConfigured: json['webhookSecretConfigured'] as bool?,
    taskAssignmentEnabled: json['taskAssignmentEnabled'] as bool?,
    taskCommentEnabled: json['taskCommentEnabled'] as bool?,
    taskStatusChangeEnabled: json['taskStatusChangeEnabled'] as bool?,
    dueDateReminderEnabled: json['dueDateReminderEnabled'] as bool?,
    dueDateReminderLeadTimeMinutes: _int(json['dueDateReminderLeadTimeMinutes']),
  );

  final String? emailAddress;
  final bool? emailEnabled;
  final bool? ntfyEnabled;
  final String? ntfyServerUrl;
  final String? ntfyTopic;
  final bool? ntfyTokenConfigured;
  final bool? gotifyEnabled;
  final String? gotifyServerUrl;
  final bool? gotifyTokenConfigured;
  final bool? webhookEnabled;
  final String? webhookUrl;
  final bool? webhookSecretConfigured;
  final bool? taskAssignmentEnabled;
  final bool? taskCommentEnabled;
  final bool? taskStatusChangeEnabled;
  final bool? dueDateReminderEnabled;
  final int? dueDateReminderLeadTimeMinutes;

  Map<String, dynamic> toJson() => {
    if (emailAddress != null) 'emailAddress': emailAddress,
    if (emailEnabled != null) 'emailEnabled': emailEnabled,
    if (ntfyEnabled != null) 'ntfyEnabled': ntfyEnabled,
    if (ntfyServerUrl != null) 'ntfyServerUrl': ntfyServerUrl,
    if (ntfyTopic != null) 'ntfyTopic': ntfyTopic,
    if (ntfyTokenConfigured != null) 'ntfyTokenConfigured': ntfyTokenConfigured,
    if (gotifyEnabled != null) 'gotifyEnabled': gotifyEnabled,
    if (gotifyServerUrl != null) 'gotifyServerUrl': gotifyServerUrl,
    if (gotifyTokenConfigured != null) 'gotifyTokenConfigured': gotifyTokenConfigured,
    if (webhookEnabled != null) 'webhookEnabled': webhookEnabled,
    if (webhookUrl != null) 'webhookUrl': webhookUrl,
    if (webhookSecretConfigured != null) 'webhookSecretConfigured': webhookSecretConfigured,
    if (taskAssignmentEnabled != null) 'taskAssignmentEnabled': taskAssignmentEnabled,
    if (taskCommentEnabled != null) 'taskCommentEnabled': taskCommentEnabled,
    if (taskStatusChangeEnabled != null) 'taskStatusChangeEnabled': taskStatusChangeEnabled,
    if (dueDateReminderEnabled != null) 'dueDateReminderEnabled': dueDateReminderEnabled,
    if (dueDateReminderLeadTimeMinutes != null)
      'dueDateReminderLeadTimeMinutes': dueDateReminderLeadTimeMinutes,
  };
}

/// Fields left null are omitted from the request, which keeps the server value.
class UpdateNotificationPreferences {
  const UpdateNotificationPreferences({
    this.emailEnabled,
    this.ntfyEnabled,
    this.ntfyServerUrl,
    this.ntfyTopic,
    this.ntfyToken,
    this.gotifyEnabled,
    this.gotifyServerUrl,
    this.gotifyToken,
    this.webhookEnabled,
    this.webhookUrl,
    this.webhookSecret,
    this.taskAssignmentEnabled,
    this.taskCommentEnabled,
    this.taskStatusChangeEnabled,
    this.dueDateReminderEnabled,
    this.dueDateReminderLeadTimeMinutes,
  });

  factory UpdateNotificationPreferences.fromJson(Map<String, dynamic> json) =>
      UpdateNotificationPreferences(
        emailEnabled: json['emailEnabled'] as bool?,
        ntfyEnabled: json['ntfyEnabled'] as bool?,
        ntfyServerUrl: json['ntfyServerUrl'] as String?,
        ntfyTopic: json['ntfyTopic'] as String?,
        ntfyToken: json['ntfyToken'] as String?,
        gotifyEnabled: json['gotifyEnabled'] as bool?,
        gotifyServerUrl: json['gotifyServerUrl'] as String?,
        gotifyToken: json['gotifyToken'] as String?,
        webhookEnabled: json['webhookEnabled'] as bool?,
        webhookUrl: json['webhookUrl'] as String?,
        webhookSecret: json['webhookSecret'] as String?,
        taskAssignmentEnabled: json['taskAssignmentEnabled'] as bool?,
        taskCommentEnabled: json['taskCommentEnabled'] as bool?,
        taskStatusChangeEnabled: json['taskStatusChangeEnabled'] as bool?,
        dueDateReminderEnabled: json['dueDateReminderEnabled'] as bool?,
        dueDateReminderLeadTimeMinutes: _int(json['dueDateReminderLeadTimeMinutes']),
      );

  final bool? emailEnabled;
  final bool? ntfyEnabled;
  final String? ntfyServerUrl;
  final String? ntfyTopic;
  final String? ntfyToken;
  final bool? gotifyEnabled;
  final String? gotifyServerUrl;
  final String? gotifyToken;
  final bool? webhookEnabled;
  final String? webhookUrl;
  final String? webhookSecret;
  final bool? taskAssignmentEnabled;
  final bool? taskCommentEnabled;
  final bool? taskStatusChangeEnabled;
  final bool? dueDateReminderEnabled;
  final int? dueDateReminderLeadTimeMinutes;

  Map<String, dynamic> toJson() => {
    if (emailEnabled != null) 'emailEnabled': emailEnabled,
    if (ntfyEnabled != null) 'ntfyEnabled': ntfyEnabled,
    if (ntfyServerUrl != null) 'ntfyServerUrl': ntfyServerUrl,
    if (ntfyTopic != null) 'ntfyTopic': ntfyTopic,
    if (ntfyToken != null) 'ntfyToken': ntfyToken,
    if (gotifyEnabled != null) 'gotifyEnabled': gotifyEnabled,
    if (gotifyServerUrl != null) 'gotifyServerUrl': gotifyServerUrl,
    if (gotifyToken != null) 'gotifyToken': gotifyToken,
    if (webhookEnabled != null) 'webhookEnabled': webhookEnabled,
    if (webhookUrl != null) 'webhookUrl': webhookUrl,
    if (webhookSecret != null) 'webhookSecret': webhookSecret,
    if (taskAssignmentEnabled != null) 'taskAssignmentEnabled': taskAssignmentEnabled,
    if (taskCommentEnabled != null) 'taskCommentEnabled': taskCommentEnabled,
    if (taskStatusChangeEnabled != null) 'taskStatusChangeEnabled': taskStatusChangeEnabled,
    if (dueDateReminderEnabled != null) 'dueDateReminderEnabled': dueDateReminderEnabled,
    if (dueDateReminderLeadTimeMinutes != null)
      'dueDateReminderLeadTimeMinutes': dueDateReminderLeadTimeMinutes,
  };
}

class SearchResult {
  const SearchResult({
    required this.id,
    required this.type,
    required this.title,
    this.content,
    this.projectId,
    this.projectName,
    this.projectSlug,
    this.workspaceId,
    this.workspaceName,
    this.userName,
    this.createdAt,
    this.taskNumber,
    this.priority,
    this.status,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    content: json['content'] as String?,
    projectId: json['projectId'] as String?,
    projectName: json['projectName'] as String?,
    projectSlug: json['projectSlug'] as String?,
    workspaceId: json['workspaceId'] as String?,
    workspaceName: json['workspaceName'] as String?,
    userName: json['userName'] as String?,
    createdAt: json['createdAt'] as String?,
    taskNumber: _int(json['taskNumber']),
    priority: json['priority'] as String?,
    status: json['status'] as String?,
  );

  final String id;
  final String type;
  final String title;
  final String? content;
  final String? projectId;
  final String? projectName;
  final String? projectSlug;
  final String? workspaceId;
  final String? workspaceName;
  final String? userName;
  final String? createdAt;
  final int? taskNumber;
  final String? priority;
  final String? status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    if (content != null) 'content': content,
    if (projectId != null) 'projectId': projectId,
    if (projectName != null) 'projectName': projectName,
    if (projectSlug != null) 'projectSlug': projectSlug,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (workspaceName != null) 'workspaceName': workspaceName,
    if (userName != null) 'userName': userName,
    if (createdAt != null) 'createdAt': createdAt,
    if (taskNumber != null) 'taskNumber': taskNumber,
    if (priority != null) 'priority': priority,
    if (status != null) 'status': status,
  };
}

class SearchResponse {
  const SearchResponse({required this.results, this.totalCount});

  factory SearchResponse.fromJson(Map<String, dynamic> json) => SearchResponse(
    results: _list(json['results'], SearchResult.fromJson) ?? const [],
    totalCount: _int(json['totalCount']),
  );

  final List<SearchResult> results;
  final int? totalCount;

  Map<String, dynamic> toJson() => {
    'results': results.map((e) => e.toJson()).toList(),
    if (totalCount != null) 'totalCount': totalCount,
  };
}

class ImageUploadResponse {
  const ImageUploadResponse({required this.key, required this.uploadUrl, this.headers});

  factory ImageUploadResponse.fromJson(Map<String, dynamic> json) => ImageUploadResponse(
    key: json['key'] as String,
    uploadUrl: json['uploadUrl'] as String,
    headers: ((json['headers']) as Map?)?.map((k, v) => MapEntry(k as String, v as String)),
  );

  final String key;
  final String uploadUrl;
  final Map<String, String>? headers;

  Map<String, dynamic> toJson() => {
    'key': key,
    'uploadUrl': uploadUrl,
    if (headers != null) 'headers': headers,
  };
}

class FinalizedAsset {
  const FinalizedAsset({required this.id, required this.url});

  factory FinalizedAsset.fromJson(Map<String, dynamic> json) =>
      FinalizedAsset(id: json['id'] as String, url: json['url'] as String);

  final String id;
  final String url;

  Map<String, dynamic> toJson() => {'id': id, 'url': url};
}

class CustomFieldInput {
  const CustomFieldInput({required this.fieldId, required this.value});

  factory CustomFieldInput.fromJson(Map<String, dynamic> json) =>
      CustomFieldInput(fieldId: json['fieldId'] as String, value: json['value'] as String);

  final String fieldId;
  final String value;

  Map<String, dynamic> toJson() => {'fieldId': fieldId, 'value': value};
}

class CreateTaskBody {
  const CreateTaskBody({
    required this.title,
    required this.description,
    this.startDate,
    this.dueDate,
    required this.priority,
    required this.status,
    this.userId,
    this.customFields,
  });

  factory CreateTaskBody.fromJson(Map<String, dynamic> json) => CreateTaskBody(
    title: json['title'] as String,
    description: json['description'] as String,
    startDate: json['startDate'] as String?,
    dueDate: json['dueDate'] as String?,
    priority: json['priority'] as String,
    status: json['status'] as String,
    userId: json['userId'] as String?,
    customFields: _list(json['customFields'], CustomFieldInput.fromJson),
  );

  final String title;
  final String description;
  final String? startDate;
  final String? dueDate;
  final String priority;
  final String status;
  final String? userId;
  final List<CustomFieldInput>? customFields;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    if (startDate != null) 'startDate': startDate,
    if (dueDate != null) 'dueDate': dueDate,
    'priority': priority,
    'status': status,
    if (userId != null) 'userId': userId,
    if (customFields != null) 'customFields': customFields!.map((e) => e.toJson()).toList(),
  };
}

class UpdateTaskBody {
  const UpdateTaskBody({
    required this.title,
    this.description,
    this.startDate,
    this.dueDate,
    required this.priority,
    required this.status,
    required this.projectId,
    required this.position,
    this.userId,
  });

  factory UpdateTaskBody.fromJson(Map<String, dynamic> json) => UpdateTaskBody(
    title: json['title'] as String,
    description: json['description'] as String?,
    startDate: json['startDate'] as String?,
    dueDate: json['dueDate'] as String?,
    priority: json['priority'] as String,
    status: json['status'] as String,
    projectId: json['projectId'] as String,
    position: _num(json['position'])!,
    userId: json['userId'] as String?,
  );

  final String title;
  final String? description;
  final String? startDate;
  final String? dueDate;
  final String priority;
  final String status;
  final String projectId;
  final num position;
  final String? userId;

  Map<String, dynamic> toJson() => {
    'title': title,
    if (description != null) 'description': description,
    if (startDate != null) 'startDate': startDate,
    if (dueDate != null) 'dueDate': dueDate,
    'priority': priority,
    'status': status,
    'projectId': projectId,
    'position': position,
    if (userId != null) 'userId': userId,
  };
}

/// One row of `reorderTasks`.
class PositionUpdate {
  const PositionUpdate({required this.id, required this.position, this.status});

  factory PositionUpdate.fromJson(Map<String, dynamic> json) => PositionUpdate(
    id: json['id'] as String,
    position: _num(json['position'])!,
    status: json['status'] as String?,
  );

  final String id;
  final num position;
  final String? status;

  Map<String, dynamic> toJson() => {
    'id': id,
    'position': position,
    if (status != null) 'status': status,
  };
}

/// One row of `reorderColumns`.
class ColumnPosition {
  const ColumnPosition({required this.id, required this.position});

  factory ColumnPosition.fromJson(Map<String, dynamic> json) =>
      ColumnPosition(id: json['id'] as String, position: _num(json['position'])!);

  final String id;
  final num position;

  Map<String, dynamic> toJson() => {'id': id, 'position': position};
}

/// What the signed-in member may do in a workspace.
class WorkspaceCapabilities {
  const WorkspaceCapabilities({
    this.manageProjects = false,
    this.createProjects = false,
    this.updateProjects = false,
    this.shareProjects = false,
    this.deleteProjects = false,
    this.updateTasks = false,
    this.createTasks = false,
    this.deleteTasks = false,
    this.assignTasks = false,
    this.createLabels = false,
    this.updateLabels = false,
    this.deleteLabels = false,
    this.manageWorkspace = false,
    this.manageSettings = false,
    this.deleteWorkspace = false,
    this.inviteUsers = false,
    this.manageTeam = false,
    this.updateMembers = false,
    this.removeMembers = false,
  });

  factory WorkspaceCapabilities.fromJson(Map<String, dynamic> json) => WorkspaceCapabilities(
    manageProjects: json['manageProjects'] == true,
    createProjects: json['createProjects'] == true,
    updateProjects: json['updateProjects'] == true,
    shareProjects: json['shareProjects'] == true,
    deleteProjects: json['deleteProjects'] == true,
    updateTasks: json['updateTasks'] == true,
    createTasks: json['createTasks'] == true,
    deleteTasks: json['deleteTasks'] == true,
    assignTasks: json['assignTasks'] == true,
    createLabels: json['createLabels'] == true,
    updateLabels: json['updateLabels'] == true,
    deleteLabels: json['deleteLabels'] == true,
    manageWorkspace: json['manageWorkspace'] == true,
    manageSettings: json['manageSettings'] == true,
    deleteWorkspace: json['deleteWorkspace'] == true,
    inviteUsers: json['inviteUsers'] == true,
    manageTeam: json['manageTeam'] == true,
    updateMembers: json['updateMembers'] == true,
    removeMembers: json['removeMembers'] == true,
  );

  final bool manageProjects;
  final bool createProjects;
  final bool updateProjects;
  final bool shareProjects;
  final bool deleteProjects;
  final bool updateTasks;
  final bool createTasks;
  final bool deleteTasks;
  final bool assignTasks;
  final bool createLabels;
  final bool updateLabels;
  final bool deleteLabels;
  final bool manageWorkspace;
  final bool manageSettings;
  final bool deleteWorkspace;
  final bool inviteUsers;
  final bool manageTeam;
  final bool updateMembers;
  final bool removeMembers;

  Map<String, dynamic> toJson() => {
    'manageProjects': manageProjects,
    'createProjects': createProjects,
    'updateProjects': updateProjects,
    'shareProjects': shareProjects,
    'deleteProjects': deleteProjects,
    'updateTasks': updateTasks,
    'createTasks': createTasks,
    'deleteTasks': deleteTasks,
    'assignTasks': assignTasks,
    'createLabels': createLabels,
    'updateLabels': updateLabels,
    'deleteLabels': deleteLabels,
    'manageWorkspace': manageWorkspace,
    'manageSettings': manageSettings,
    'deleteWorkspace': deleteWorkspace,
    'inviteUsers': inviteUsers,
    'manageTeam': manageTeam,
    'updateMembers': updateMembers,
    'removeMembers': removeMembers,
  };
}
