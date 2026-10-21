import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../security/input_validator.dart';

/// Tukar sebarang nilai masa (Timestamp / DateTime / int ms / String) kepada
/// rentetan ISO-8601 supaya UI boleh memaparkannya secara seragam.
String readTime(dynamic value) {
  if (value == null) return '';
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is DateTime) return value.toIso8601String();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value).toIso8601String();
  }
  return value.toString();
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _asString(dynamic value, [String fallback = '']) =>
    value?.toString() ?? fallback;

// ============================================================================
// Pengguna
// ============================================================================

class AppUser {
  static const roles = ['student', 'admin'];
  static const relationships = ['Mother', 'Father', 'Guardian', 'Other'];

  final String uid;
  final String email;
  final String role;
  final String status;
  final String authProvider;
  final String fullName;
  final String matricNo;
  final String course;
  final String semester;
  final String phone;
  final String parentName;
  final String parentEmail;
  final String parentPhone;
  final String relationship;
  final int profileCompletePercent;
  final String privacyVersion;
  final int unreadNotifications;
  final String createdAt;
  final String updatedAt;

  const AppUser({
    required this.uid,
    required this.email,
    this.role = 'student',
    this.status = 'active',
    this.authProvider = 'password',
    required this.fullName,
    this.matricNo = '',
    this.course = '',
    this.semester = '',
    this.phone = '',
    this.parentName = '',
    this.parentEmail = '',
    this.parentPhone = '',
    this.relationship = '',
    this.profileCompletePercent = 0,
    this.privacyVersion = '',
    this.unreadNotifications = 0,
    this.createdAt = '',
    this.updatedAt = '',
  });

  bool get isAdmin => role == 'admin';
  bool get isStudent => role == 'student';
  bool get isSuspended => status == 'suspended';

  bool get hasCompleteStudentProfile =>
      fullName.trim().isNotEmpty &&
      matricNo.trim().isNotEmpty &&
      course.trim().isNotEmpty &&
      semester.trim().isNotEmpty &&
      phone.trim().isNotEmpty;

  bool get hasParentInfo =>
      parentName.trim().isNotEmpty &&
      InputValidator.validateEmail(parentEmail) == null &&
      parentPhone.trim().isNotEmpty &&
      relationship.trim().isNotEmpty;

  bool get canJoinPrograms =>
      isStudent && !isSuspended && hasCompleteStudentProfile && hasParentInfo;

  /// Peratus kelengkapan profil (dikira, bukan dipercayai daripada klien).
  static int computeProfilePercent(AppUser u) {
    final fields = [
      u.fullName,
      u.matricNo,
      u.course,
      u.semester,
      u.phone,
      u.parentName,
      u.parentEmail,
      u.parentPhone,
      u.relationship,
    ];
    final filled = fields.where((value) => value.trim().isNotEmpty).length;
    if (u.hasCompleteStudentProfile && u.hasParentInfo) return 100;
    return ((filled / fields.length) * 100).floor().clamp(0, 99);
  }

  AppUser copyWith({
    String? role,
    String? status,
    String? fullName,
    String? matricNo,
    String? course,
    String? semester,
    String? phone,
    String? parentName,
    String? parentEmail,
    String? parentPhone,
    String? relationship,
    int? profileCompletePercent,
    String? privacyVersion,
    int? unreadNotifications,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      role: role ?? this.role,
      status: status ?? this.status,
      authProvider: authProvider,
      fullName: fullName ?? this.fullName,
      matricNo: matricNo ?? this.matricNo,
      course: course ?? this.course,
      semester: semester ?? this.semester,
      phone: phone ?? this.phone,
      parentName: parentName ?? this.parentName,
      parentEmail: parentEmail ?? this.parentEmail,
      parentPhone: parentPhone ?? this.parentPhone,
      relationship: relationship ?? this.relationship,
      profileCompletePercent:
          profileCompletePercent ?? this.profileCompletePercent,
      privacyVersion: privacyVersion ?? this.privacyVersion,
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory AppUser.fromMap(Map<dynamic, dynamic> map) {
    return AppUser(
      uid: _asString(map['uid']),
      email: _asString(map['email']),
      role: roles.contains(map['role']) ? map['role'] as String : 'student',
      status: map['status'] == 'suspended' ? 'suspended' : 'active',
      authProvider: _asString(map['authProvider'], 'password'),
      fullName: _asString(map['fullName']),
      matricNo: _asString(map['matricNo']),
      course: _asString(map['course']),
      semester: _asString(map['semester']),
      phone: _asString(map['phone']),
      parentName: _asString(map['parentName']),
      parentEmail: _asString(map['parentEmail']),
      parentPhone: _asString(map['parentPhone']),
      relationship: _asString(map['relationship']),
      profileCompletePercent: _asInt(map['profileCompletePercent']),
      privacyVersion: _asString(map['privacyVersion']),
      unreadNotifications: _asInt(map['unreadNotifications']),
      createdAt: readTime(map['createdAt']),
      updatedAt: readTime(map['updatedAt']),
    );
  }

  /// Medan profil yang boleh diubah oleh pemilik (selaras dengan firestore.rules).
  Map<String, dynamic> toProfileMap() {
    return {
      'fullName': fullName.trim(),
      'matricNo': matricNo.trim(),
      'course': course.trim(),
      'semester': semester.trim(),
      'phone': phone.trim(),
      'parentName': parentName.trim(),
      'parentEmail': parentEmail.trim().toLowerCase(),
      'parentPhone': parentPhone.trim(),
      'relationship': relationship,
      'profileCompletePercent': computeProfilePercent(this),
      'privacyVersion': privacyVersion,
    };
  }

  /// Dokumen penuh semasa pendaftaran (cap masa diisi oleh repositori).
  Map<String, dynamic> toNewUserMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'status': 'active',
      'authProvider': authProvider,
      ...toProfileMap(),
      'unreadNotifications': 0,
    };
  }

  Map<String, dynamic> toMap() => {
    ...toNewUserMap(),
    'status': status,
    'unreadNotifications': unreadNotifications,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

// ============================================================================
// Program
// ============================================================================

class MediaRef {
  final String id;
  final String kind; // image | video
  final String url;
  final String caption;

  const MediaRef({
    required this.id,
    required this.kind,
    this.url = '',
    this.caption = '',
  });

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';

  factory MediaRef.fromMap(Map<dynamic, dynamic> map) => MediaRef(
    id: _asString(map['id']),
    kind: map['kind'] == 'video' ? 'video' : 'image',
    url: _asString(map['url']),
    caption: _asString(map['caption']),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind,
    'url': url,
    'caption': caption,
  };
}

class Program {
  /// Status yang disimpan. "Penuh" kini dikira daripada kaunter tempat.
  static const statuses = <String>[
    'draft',
    'open',
    'closed',
    'cancelled',
    'completed',
    'archived',
  ];

  static const categories = <String>[
    'Academic',
    'Sports',
    'Leadership',
    'Career',
    'Volunteer',
  ];

  /// Status yang dipaparkan dalam katalog pelajar.
  static const catalogStatuses = <String>[
    'open',
    'closed',
    'cancelled',
    'completed',
  ];

  final String id;
  final String title;
  final String description;
  final String date;
  final String time;
  final String location;
  final int capacity;
  final String category;
  final String status;
  final String cancellationReason;
  final String coverMediaId;
  final List<MediaRef> gallery;
  final int seatShards;
  final String createdBy;
  final String createdAt;
  final String updatedAt;

  /// Nilai masa jalan daripada kaunter shard (tidak disimpan dalam dokumen).
  final int joinedCount;

  const Program({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    required this.location,
    required this.capacity,
    required this.category,
    this.status = 'draft',
    this.cancellationReason = '',
    this.coverMediaId = '',
    this.gallery = const [],
    this.seatShards = 0,
    this.createdBy = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.joinedCount = 0,
  });

  bool get isFull => capacity > 0 && joinedCount >= capacity;

  /// Status untuk paparan: "full" apabila dibuka tetapi tiada tempat lagi.
  String get displayStatus => status == 'open' && isFull ? 'full' : status;

  bool get isInCatalog => catalogStatuses.contains(status);
  bool get isVisibleToStudents => status == 'open';
  bool get canJoin => status == 'open' && !isFull;
  int get remainingSlots => (capacity - joinedCount).clamp(0, capacity);
  double get fillRate =>
      capacity == 0 ? 0 : (joinedCount / capacity).clamp(0.0, 1.0);

  List<MediaRef> get images => gallery.where((m) => m.isImage).toList();
  List<MediaRef> get videos => gallery.where((m) => m.isVideo).toList();

  Program copyWith({
    String? id,
    String? title,
    String? description,
    String? date,
    String? time,
    String? location,
    int? capacity,
    String? category,
    String? status,
    String? cancellationReason,
    String? coverMediaId,
    List<MediaRef>? gallery,
    int? seatShards,
    String? createdBy,
    String? createdAt,
    String? updatedAt,
    int? joinedCount,
  }) {
    return Program(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      time: time ?? this.time,
      location: location ?? this.location,
      capacity: capacity ?? this.capacity,
      category: category ?? this.category,
      status: status ?? this.status,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      coverMediaId: coverMediaId ?? this.coverMediaId,
      gallery: gallery ?? this.gallery,
      seatShards: seatShards ?? this.seatShards,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      joinedCount: joinedCount ?? this.joinedCount,
    );
  }

  factory Program.fromMap(Map<dynamic, dynamic> map) {
    final rawStatus = _asString(map['status'], 'draft');
    final galleryRaw = map['gallery'];
    return Program(
      id: _asString(map['id']),
      title: _asString(map['title']),
      description: _asString(map['description']),
      date: _asString(map['date']),
      time: _asString(map['time']),
      location: _asString(map['location']),
      capacity: _asInt(map['capacity']),
      category: categories.contains(map['category'])
          ? map['category'] as String
          : 'Academic',
      // Data lama menggunakan "full" sebagai status tersimpan.
      status: rawStatus == 'full'
          ? 'open'
          : statuses.contains(rawStatus)
          ? rawStatus
          : 'draft',
      cancellationReason: _asString(map['cancellationReason']),
      coverMediaId: _asString(map['coverMediaId']),
      gallery: galleryRaw is List
          ? galleryRaw
                .whereType<Map>()
                .map((item) => MediaRef.fromMap(item))
                .where((m) => m.id.isNotEmpty)
                .toList()
          : const [],
      seatShards: _asInt(map['seatShards']),
      createdBy: _asString(map['createdBy']),
      createdAt: readTime(map['createdAt']),
      updatedAt: readTime(map['updatedAt']),
      joinedCount: _asInt(map['joinedCount']),
    );
  }

  /// Dokumen penuh `programs/{id}` (admin sahaja).
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title.trim(),
    'description': description.trim(),
    'date': date,
    'time': time,
    'location': location.trim(),
    'capacity': capacity,
    'category': category,
    'status': status,
    'cancellationReason': cancellationReason.trim(),
    'coverMediaId': coverMediaId,
    'gallery': gallery.map((m) => m.toMap()).toList(),
    'seatShards': seatShards,
    'createdBy': createdBy,
  };

  /// Unjuran awam yang disimpan dalam `public/catalog`.
  Map<String, dynamic> toCatalogMap() => {
    'id': id,
    'title': title.trim(),
    'description': description.trim(),
    'date': date,
    'time': time,
    'location': location.trim(),
    'capacity': capacity,
    'category': category,
    'status': status,
    'cancellationReason': cancellationReason.trim(),
    'coverMediaId': coverMediaId,
    'gallery': gallery.map((m) => m.toMap()).toList(),
    'seatShards': seatShards,
    'updatedAt': updatedAt,
  };
}

// ============================================================================
// Kaunter tempat (shard)
// ============================================================================

class SeatShard {
  final String id;
  final int count;
  final int cap;

  const SeatShard({required this.id, required this.count, required this.cap});

  bool get isFull => count >= cap;
  int get free => (cap - count).clamp(0, cap);

  factory SeatShard.fromMap(String id, Map<dynamic, dynamic> map) =>
      SeatShard(id: id, count: _asInt(map['count']), cap: _asInt(map['cap']));
}

class SeatSummary {
  final int joined;
  final int capacity;

  const SeatSummary({required this.joined, required this.capacity});

  int get remaining => (capacity - joined).clamp(0, capacity);
  bool get isFull => capacity > 0 && joined >= capacity;
}

// ============================================================================
// Penyertaan
// ============================================================================

class Participant {
  final String studentUid;
  final String studentName;
  final String studentEmail;
  final String matricNo;
  final String course;
  final String semester;
  final String studentPhone;
  final String parentName;
  final String parentEmail;
  final String parentPhone;
  final String relationship;
  final String programId;
  final String programTitle;
  final String programDate;
  final String programTime;
  final String programLocation;
  final String joinedAt;
  final String emailStatus;
  final String seatShard;

  const Participant({
    required this.studentUid,
    required this.studentName,
    required this.studentEmail,
    this.matricNo = '',
    this.course = '',
    this.semester = '',
    this.studentPhone = '',
    this.parentName = '',
    required this.parentEmail,
    this.parentPhone = '',
    this.relationship = '',
    this.programId = '',
    this.programTitle = '',
    this.programDate = '',
    this.programTime = '',
    this.programLocation = '',
    required this.joinedAt,
    this.emailStatus = 'pending',
    this.seatShard = '',
  });

  factory Participant.fromStudent({
    required AppUser student,
    required Program program,
    required String seatShard,
  }) {
    return Participant(
      studentUid: student.uid,
      studentName: student.fullName,
      studentEmail: student.email,
      matricNo: student.matricNo,
      course: student.course,
      semester: student.semester,
      studentPhone: student.phone,
      parentName: student.parentName,
      parentEmail: student.parentEmail.trim().toLowerCase(),
      parentPhone: student.parentPhone,
      relationship: student.relationship,
      programId: program.id,
      programTitle: program.title,
      programDate: program.date,
      programTime: program.time,
      programLocation: program.location,
      joinedAt: '',
      seatShard: seatShard,
    );
  }

  Participant copyWith({String? emailStatus}) => Participant(
    studentUid: studentUid,
    studentName: studentName,
    studentEmail: studentEmail,
    matricNo: matricNo,
    course: course,
    semester: semester,
    studentPhone: studentPhone,
    parentName: parentName,
    parentEmail: parentEmail,
    parentPhone: parentPhone,
    relationship: relationship,
    programId: programId,
    programTitle: programTitle,
    programDate: programDate,
    programTime: programTime,
    programLocation: programLocation,
    joinedAt: joinedAt,
    emailStatus: emailStatus ?? this.emailStatus,
    seatShard: seatShard,
  );

  factory Participant.fromMap(Map<dynamic, dynamic> map) {
    return Participant(
      studentUid: _asString(map['studentUid']),
      studentName: _asString(map['studentName']),
      studentEmail: _asString(map['studentEmail']),
      matricNo: _asString(map['matricNo']),
      course: _asString(map['course']),
      semester: _asString(map['semester']),
      studentPhone: _asString(map['studentPhone']),
      parentName: _asString(map['parentName']),
      parentEmail: _asString(map['parentEmail']),
      parentPhone: _asString(map['parentPhone']),
      relationship: _asString(map['relationship']),
      programId: _asString(map['programId']),
      programTitle: _asString(map['programTitle']),
      programDate: _asString(map['programDate']),
      programTime: _asString(map['programTime']),
      programLocation: _asString(map['programLocation']),
      joinedAt: readTime(map['joinedAt']),
      emailStatus: _asString(map['emailStatus'], 'pending'),
      seatShard: _asString(map['seatShard']),
    );
  }

  /// Medan yang ditulis semasa sertai (cap masa diisi oleh repositori).
  Map<String, dynamic> toJoinMap() => {
    'studentUid': studentUid,
    'studentName': studentName,
    'studentEmail': studentEmail,
    'matricNo': matricNo,
    'course': course,
    'semester': semester,
    'studentPhone': studentPhone,
    'parentName': parentName,
    'parentEmail': parentEmail,
    'parentPhone': parentPhone,
    'relationship': relationship,
    'programId': programId,
    'programTitle': programTitle,
    'programDate': programDate,
    'programTime': programTime,
    'programLocation': programLocation,
    'emailStatus': 'pending',
    'seatShard': seatShard,
  };

  Map<String, dynamic> toMap() => {
    ...toJoinMap(),
    'joinedAt': joinedAt,
    'emailStatus': emailStatus,
  };
}

// ============================================================================
// Pengumuman, notifikasi & emel
// ============================================================================

class Announcement {
  final String id;
  final String title;
  final String message;
  final String target;
  final String createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    this.target = 'all',
    required this.createdAt,
  });

  factory Announcement.fromMap(Map<dynamic, dynamic> map) {
    return Announcement(
      id: _asString(map['id']),
      title: _asString(map['title']),
      message: _asString(map['message']),
      target: _asString(map['target'], 'all'),
      createdAt: readTime(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'message': message,
    'target': target,
    'createdAt': createdAt,
  };
}

class StudentNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final String programId;
  final String createdAt;
  final bool isRead;

  const StudentNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.programId = '',
    required this.createdAt,
    this.isRead = false,
  });

  factory StudentNotification.fromMap(Map<dynamic, dynamic> map) {
    return StudentNotification(
      id: _asString(map['id']),
      type: _asString(map['type'], 'info'),
      title: _asString(map['title']),
      message: _asString(map['message']),
      programId: _asString(map['programId']),
      createdAt: readTime(map['createdAt']),
      isRead: map['isRead'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'title': title,
    'message': message,
    'programId': programId,
    'isRead': isRead,
  };
}

class EmailLog {
  static const statuses = ['queued', 'sending', 'sent', 'failed'];

  final String id;
  final String recipient;
  final String subject;
  final String body;
  final String status;
  final String errorMessage;
  final String studentName;
  final String studentUid;
  final String programId;
  final String programTitle;
  final String type;
  final String createdBy;
  final String createdAt;
  final String updatedAt;
  final int attempts;

  const EmailLog({
    required this.id,
    required this.recipient,
    required this.subject,
    required this.body,
    required this.status,
    this.errorMessage = '',
    required this.studentName,
    this.studentUid = '',
    this.programId = '',
    required this.programTitle,
    this.type = 'join',
    this.createdBy = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.attempts = 0,
  });

  /// Keserasian dengan UI lama.
  String get sentTime => updatedAt.isNotEmpty ? updatedAt : createdAt;

  EmailLog copyWith({String? status, String? errorMessage, int? attempts}) =>
      EmailLog(
        id: id,
        recipient: recipient,
        subject: subject,
        body: body,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        studentName: studentName,
        studentUid: studentUid,
        programId: programId,
        programTitle: programTitle,
        type: type,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
        attempts: attempts ?? this.attempts,
      );

  factory EmailLog.fromMap(Map<dynamic, dynamic> map) {
    final status = _asString(map['status'], 'queued');
    return EmailLog(
      id: _asString(map['id']),
      recipient: _asString(map['recipient']),
      subject: _asString(map['subject']),
      body: _asString(map['body']),
      status: statuses.contains(status) ? status : 'queued',
      errorMessage: _asString(map['errorMessage']),
      studentName: _asString(map['studentName']),
      studentUid: _asString(map['studentUid']),
      programId: _asString(map['programId']),
      programTitle: _asString(map['programTitle']),
      type: _asString(map['type'], 'join'),
      createdBy: _asString(map['createdBy']),
      createdAt: readTime(map['createdAt'] ?? map['sentTime']),
      updatedAt: readTime(map['updatedAt']),
      attempts: _asInt(map['attempts']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'recipient': recipient,
    'subject': subject,
    'body': body,
    'status': status,
    'errorMessage': errorMessage,
    'studentName': studentName,
    'studentUid': studentUid,
    'programId': programId,
    'programTitle': programTitle,
    'type': type,
    'createdBy': createdBy,
    'attempts': attempts,
  };
}

// ============================================================================
// Media (gambar dalam Firestore, video sebagai pautan)
// ============================================================================

class MediaItem {
  final String id;
  final String programId;
  final String kind;
  final Uint8List? bytes;
  final String contentType;
  final int sizeBytes;
  final int width;
  final int height;
  final String url;
  final String caption;
  final String uploadedBy;
  final String createdAt;

  const MediaItem({
    required this.id,
    required this.programId,
    required this.kind,
    this.bytes,
    this.contentType = '',
    this.sizeBytes = 0,
    this.width = 0,
    this.height = 0,
    this.url = '',
    this.caption = '',
    this.uploadedBy = '',
    this.createdAt = '',
  });

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';

  MediaRef toRef() => MediaRef(id: id, kind: kind, url: url, caption: caption);

  factory MediaItem.fromMap(Map<dynamic, dynamic> map) {
    final raw = map['bytes'];
    Uint8List? bytes;
    if (raw is Blob) bytes = raw.bytes;
    if (raw is Uint8List) bytes = raw;
    return MediaItem(
      id: _asString(map['id']),
      programId: _asString(map['programId']),
      kind: map['kind'] == 'video' ? 'video' : 'image',
      bytes: bytes,
      contentType: _asString(map['contentType']),
      sizeBytes: _asInt(map['sizeBytes']),
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      url: _asString(map['url']),
      caption: _asString(map['caption']),
      uploadedBy: _asString(map['uploadedBy']),
      createdAt: readTime(map['createdAt']),
    );
  }
}

// ============================================================================
// Ruang kerja admin (RTDB)
// ============================================================================

class AuditEntry {
  final String id;
  final String action;
  final String actorUid;
  final String actorEmail;
  final String summary;
  final String targetType;
  final String targetId;
  final int at;

  const AuditEntry({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.actorEmail,
    required this.summary,
    this.targetType = '',
    this.targetId = '',
    required this.at,
  });

  String get atIso => readTime(at);

  factory AuditEntry.fromMap(String id, Map<dynamic, dynamic> map) =>
      AuditEntry(
        id: id,
        action: _asString(map['action']),
        actorUid: _asString(map['actorUid']),
        actorEmail: _asString(map['actorEmail']),
        summary: _asString(map['summary']),
        targetType: _asString(map['targetType']),
        targetId: _asString(map['targetId']),
        at: _asInt(map['at']),
      );
}

class AdminPresence {
  final String uid;
  final String email;
  final String name;
  final bool online;
  final int lastSeen;

  const AdminPresence({
    required this.uid,
    required this.email,
    required this.name,
    required this.online,
    required this.lastSeen,
  });

  factory AdminPresence.fromMap(String uid, Map<dynamic, dynamic> map) =>
      AdminPresence(
        uid: uid,
        email: _asString(map['email']),
        name: _asString(map['name']),
        online: map['online'] == true,
        lastSeen: _asInt(map['lastSeen']),
      );
}

class BackupRecord {
  final String id;
  final int at;
  final String by;
  final String byEmail;
  final int documents;
  final int bytes;
  final String kind;
  final String note;

  const BackupRecord({
    required this.id,
    required this.at,
    required this.by,
    required this.byEmail,
    required this.documents,
    required this.bytes,
    required this.kind,
    this.note = '',
  });

  factory BackupRecord.fromMap(String id, Map<dynamic, dynamic> map) =>
      BackupRecord(
        id: id,
        at: _asInt(map['at']),
        by: _asString(map['by']),
        byEmail: _asString(map['byEmail']),
        documents: _asInt(map['documents']),
        bytes: _asInt(map['bytes']),
        kind: _asString(map['kind'], 'backup'),
        note: _asString(map['note']),
      );

  /// Backup harian daripada automasi Google Apps Script (apps_script/Code.gs).
  bool get isAutomatic => by == 'apps-script';
}

/// Status penghantaran emel automatik (Apps Script) – ditulis oleh skrip ke
/// RTDB admin_workspace/automation/email apabila keadaan berubah.
class AutomationStatus {
  final bool ok;
  final String message;
  final String code;
  final int at;

  const AutomationStatus({
    required this.ok,
    this.message = '',
    this.code = '',
    this.at = 0,
  });

  factory AutomationStatus.fromMap(Map<dynamic, dynamic> map) => AutomationStatus(
    ok: map['ok'] == true,
    message: _asString(map['message']),
    code: _asString(map['code']),
    at: _asInt(map['at']),
  );
}

// ============================================================================
// Hasil operasi
// ============================================================================

class JoinOutcome {
  final bool success;
  final String code;
  final String message;
  final String emailStatus;

  const JoinOutcome({
    required this.success,
    required this.code,
    required this.message,
    this.emailStatus = 'pending',
  });
}

class Catalog {
  final List<Program> programs;
  final List<Announcement> announcements;
  final bool fromCache;

  const Catalog({
    this.programs = const [],
    this.announcements = const [],
    this.fromCache = false,
  });

  static const empty = Catalog();

  factory Catalog.fromMap(Map<dynamic, dynamic>? map, {bool fromCache = false}) {
    if (map == null) return Catalog(fromCache: fromCache);
    final programsRaw = map['programs'];
    final announcementsRaw = map['announcements'];
    final programs = programsRaw is Map
        ? programsRaw.values
              .whereType<Map>()
              .map(Program.fromMap)
              .where((p) => p.id.isNotEmpty)
              .toList()
        : <Program>[];
    programs.sort((a, b) => a.date.compareTo(b.date));
    final announcements = announcementsRaw is Map
        ? announcementsRaw.values
              .whereType<Map>()
              .map(Announcement.fromMap)
              .toList()
        : <Announcement>[];
    announcements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Catalog(
      programs: programs,
      announcements: announcements,
      fromCache: fromCache,
    );
  }
}
