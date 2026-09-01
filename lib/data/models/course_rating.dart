import 'common.dart';

class CourseRatingCourse {
  const CourseRatingCourse({
    required this.id,
    required this.name,
    this.courseCode = '',
    this.courseCodes = const [],
    this.count = 0,
  });

  final int id;
  final String name;
  final String courseCode;
  final List<String> courseCodes;
  final int count;

  String get displayCode {
    if (courseCodes.isNotEmpty) {
      return courseCodes.join(' / ');
    }
    if (courseCode.isNotEmpty && courseCode != name) {
      return courseCode;
    }
    return '';
  }

  String get lookupForTeachers {
    if (displayCode.isNotEmpty) {
      return courseCodes.isNotEmpty ? courseCodes.first : courseCode;
    }
    if (id > 0) {
      return id.toString();
    }
    return name;
  }

  String get lookupForRatings {
    if (displayCode.isNotEmpty) {
      return courseCodes.isNotEmpty ? courseCodes.first : courseCode;
    }
    return name.isNotEmpty ? name : id.toString();
  }

  JsonMap toJson() {
    return {
      'id': id,
      'name': name,
      'courseCode': courseCode,
      'courseCodes': courseCodes,
      'count': count,
    };
  }

  factory CourseRatingCourse.fromJson(JsonMap json) {
    final codes = (json['CourseCodes'] as List? ??
            json['courseCodes'] as List? ??
            json['course_codes'] as List? ??
            const [])
        .map((value) => stringValue(value).trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final code = stringValue(
      json['CourseCode'] ?? json['courseCode'] ?? json['course_code'],
    ).trim();
    return CourseRatingCourse(
      id: intValue(json['ID'] ?? json['id'] ?? json['course_id']),
      name: stringValue(json['Name'] ?? json['name'] ?? json['course_name'])
          .trim(),
      courseCode: code,
      courseCodes: codes,
      count: intValue(json['Count'] ?? json['count']),
    );
  }
}

class CourseRatingTeacher {
  const CourseRatingTeacher({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  JsonMap toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  factory CourseRatingTeacher.fromJson(JsonMap json) {
    return CourseRatingTeacher(
      id: intValue(json['ID'] ?? json['id'] ?? json['teacher_id']),
      name: stringValue(json['Name'] ?? json['name'] ?? json['teacher_name'])
          .trim(),
    );
  }
}

class CourseRatingSearchResult {
  const CourseRatingSearchResult({
    required this.query,
    required this.courses,
    required this.teachers,
  });

  final String query;
  final List<CourseRatingCourse> courses;
  final List<CourseRatingTeacher> teachers;

  bool get isEmpty => courses.isEmpty && teachers.isEmpty;

  JsonMap toJson() {
    return {
      'query': query,
      'courses': courses.map((course) => course.toJson()).toList(),
      'teachers': teachers.map((teacher) => teacher.toJson()).toList(),
    };
  }

  factory CourseRatingSearchResult.fromJson(JsonMap json) {
    return CourseRatingSearchResult(
      query: stringValue(json['query']).trim(),
      courses: (json['courses'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(CourseRatingCourse.fromJson)
          .where((course) => course.name.isNotEmpty)
          .toList(growable: false),
      teachers: (json['teachers'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(CourseRatingTeacher.fromJson)
          .where((teacher) => teacher.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class CourseRatingLatestItem {
  const CourseRatingLatestItem({
    required this.id,
    required this.courseId,
    required this.teacherId,
    required this.user,
    required this.score,
    required this.content,
    required this.createdAt,
    required this.upvotes,
    required this.courseCode,
    required this.courseName,
    required this.teacherName,
  });

  final int id;
  final int courseId;
  final int teacherId;
  final CourseRatingUser user;
  final int score;
  final String content;
  final DateTime? createdAt;
  final int upvotes;
  final String courseCode;
  final String courseName;
  final String teacherName;

  JsonMap toJson() => {
        'id': id,
        'courseId': courseId,
        'teacherId': teacherId,
        'user': user.toJson(),
        'score': score,
        'content': content,
        'createdAt': createdAt?.millisecondsSinceEpoch,
        'upvotes': upvotes,
        'courseCode': courseCode,
        'courseName': courseName,
        'teacherName': teacherName,
      };

  factory CourseRatingLatestItem.fromJson(JsonMap json) {
    final user = json['user'];
    return CourseRatingLatestItem(
      id: intValue(json['ID'] ?? json['id']),
      courseId: intValue(json['CourseID'] ?? json['courseId'] ?? json['course_id']),
      teacherId: intValue(json['TeacherID'] ?? json['teacherId'] ?? json['teacher_id']),
      user: user is JsonMap
          ? CourseRatingUser.fromJson(user)
          : const CourseRatingUser(id: 0, username: '匿名'),
      score: intValue(json['Score'] ?? json['score'], -1),
      content: stringValue(json['Content'] ?? json['content']).trim(),
      createdAt: _dateFromTimestamp(json['CreatedAt'] ?? json['createdAt']),
      upvotes: intValue(json['Upvotes'] ?? json['upvotes']),
      courseCode: stringValue(json['course_code'] ?? json['courseCode']).trim(),
      courseName: stringValue(json['course_name'] ?? json['courseName']).trim(),
      teacherName: stringValue(json['teacher_name'] ?? json['teacherName']).trim(),
    );
  }
}

class CourseRatingLatestResult {
  const CourseRatingLatestResult({required this.ratings});

  final List<CourseRatingLatestItem> ratings;

  JsonMap toJson() => {
        'ratings': ratings.map((rating) => rating.toJson()).toList(),
      };

  factory CourseRatingLatestResult.fromJson(JsonMap json) {
    return CourseRatingLatestResult(
      ratings: (json['ratings'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(CourseRatingLatestItem.fromJson)
          .where((rating) => rating.courseName.isNotEmpty || rating.content.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class CourseRatingCourseTeachers {
  const CourseRatingCourseTeachers({
    required this.course,
    required this.teachers,
  });

  final CourseRatingCourse course;
  final List<CourseRatingTeacher> teachers;

  JsonMap toJson() {
    return {
      'course': course.toJson(),
      'teachers': teachers.map((teacher) => teacher.toJson()).toList(),
    };
  }

  factory CourseRatingCourseTeachers.fromJson(JsonMap json) {
    final course = json['course'];
    return CourseRatingCourseTeachers(
      course: course is JsonMap
          ? CourseRatingCourse.fromJson(course)
          : const CourseRatingCourse(id: 0, name: ''),
      teachers: (json['teachers'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(CourseRatingTeacher.fromJson)
          .where((teacher) => teacher.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class CourseRatingTeacherCourses {
  const CourseRatingTeacherCourses({
    required this.teacher,
    required this.courses,
  });

  final CourseRatingTeacher teacher;
  final List<CourseRatingCourse> courses;

  JsonMap toJson() {
    return {
      'teacher': teacher.toJson(),
      'courses': courses.map((course) => course.toJson()).toList(),
    };
  }

  factory CourseRatingTeacherCourses.fromJson(JsonMap json) {
    final teacher = json['teacher'];
    return CourseRatingTeacherCourses(
      teacher: teacher is JsonMap
          ? CourseRatingTeacher.fromJson(teacher)
          : const CourseRatingTeacher(id: 0, name: ''),
      courses: (json['courses'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(CourseRatingCourse.fromJson)
          .where((course) => course.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class CourseRatingUser {
  const CourseRatingUser({
    required this.id,
    required this.username,
  });

  final int id;
  final String username;

  JsonMap toJson() {
    return {
      'id': id,
      'username': username,
    };
  }

  factory CourseRatingUser.fromJson(JsonMap json) {
    return CourseRatingUser(
      id: intValue(json['id'] ?? json['ID']),
      username: stringValue(json['username'] ?? json['Name']).trim(),
    );
  }
}

class CourseRatingTag {
  const CourseRatingTag({
    required this.id,
    required this.name,
    this.prefix = '',
    this.category = '',
    this.weight = 0,
  });

  final int id;
  final String name;
  final String prefix;
  final String category;
  final int weight;

  String get displayText {
    if (prefix.isEmpty || name.startsWith(prefix)) {
      return name;
    }
    return '$prefix：$name';
  }

  JsonMap toJson() {
    return {
      'id': id,
      'name': name,
      'prefix': prefix,
      'category': category,
      'weight': weight,
    };
  }

  factory CourseRatingTag.fromJson(JsonMap json) {
    return CourseRatingTag(
      id: intValue(json['id'] ?? json['ID']),
      name: stringValue(json['name'] ?? json['Name']).trim(),
      prefix: stringValue(json['prefix']).trim(),
      category: stringValue(json['category']).trim(),
      weight: intValue(json['weight']),
    );
  }
}

class CourseRatingItem {
  const CourseRatingItem({
    required this.id,
    required this.score,
    required this.content,
    required this.createdAt,
    required this.upvotes,
    required this.user,
    this.tags = const [],
  });

  final int id;
  final int score;
  final String content;
  final DateTime? createdAt;
  final int upvotes;
  final CourseRatingUser user;
  final List<CourseRatingTag> tags;

  bool get hasScore => score >= 1;

  JsonMap toJson() {
    return {
      'id': id,
      'score': score,
      'content': content,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'upvotes': upvotes,
      'user': user.toJson(),
      'tags': tags.map((tag) => tag.toJson()).toList(),
    };
  }

  factory CourseRatingItem.fromJson(JsonMap json) {
    final user = json['user'];
    final tags = json['tags'];
    return CourseRatingItem(
      id: intValue(json['ID'] ?? json['id']),
      score: intValue(json['Score'] ?? json['score'], -1),
      content: stringValue(json['Content'] ?? json['content']).trim(),
      createdAt: _dateFromTimestamp(json['CreatedAt'] ?? json['createdAt']),
      upvotes: intValue(json['Upvotes'] ?? json['upvotes']),
      user: user is JsonMap
          ? CourseRatingUser.fromJson(user)
          : const CourseRatingUser(id: 0, username: '匿名'),
      tags: tags is List
          ? tags
              .whereType<JsonMap>()
              .map(CourseRatingTag.fromJson)
              .where((tag) => tag.name.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }
}

class CourseRatingRadar {
  const CourseRatingRadar({
    required this.categories,
    required this.values,
  });

  final List<String> categories;
  final List<double> values;

  bool get isNotEmpty => categories.isNotEmpty && values.isNotEmpty;

  JsonMap toJson() {
    return {
      'categories': categories,
      'values': values,
    };
  }

  factory CourseRatingRadar.fromJson(JsonMap json) {
    return CourseRatingRadar(
      categories: (json['categories'] as List? ?? const [])
          .map((value) => stringValue(value).trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      values: (json['values'] as List? ?? const [])
          .map(_doubleValue)
          .toList(growable: false),
    );
  }
}

class CourseRatingDetail {
  const CourseRatingDetail({
    required this.course,
    required this.teacher,
    required this.average,
    required this.total,
    required this.page,
    required this.perPage,
    required this.ratings,
    required this.radar,
  });

  final CourseRatingCourse course;
  final CourseRatingTeacher teacher;
  final double average;
  final int total;
  final int page;
  final int perPage;
  final List<CourseRatingItem> ratings;
  final CourseRatingRadar radar;

  bool get hasMore => page * perPage < total;

  JsonMap toJson() {
    return {
      'course': course.toJson(),
      'teacher': teacher.toJson(),
      'average': average,
      'total': total,
      'page': page,
      'perPage': perPage,
      'ratings': ratings.map((rating) => rating.toJson()).toList(),
      'radar': radar.toJson(),
    };
  }

  factory CourseRatingDetail.fromJson(JsonMap json) {
    final courseJson = json['course'];
    final teacherJson = json['teacher'];
    final course = courseJson is JsonMap
        ? CourseRatingCourse.fromJson(courseJson)
        : CourseRatingCourse.fromJson({
            'ID': json['course_id'],
            'Name': json['course_name'],
            'CourseCodes': json['course_codes'],
          });
    final teacher = teacherJson is JsonMap
        ? CourseRatingTeacher.fromJson(teacherJson)
        : CourseRatingTeacher.fromJson({
            'ID': json['teacher_id'],
            'Name': json['teacher_name'],
          });
    final ratings = (json['ratings'] as List? ?? const [])
        .whereType<JsonMap>()
        .map(CourseRatingItem.fromJson)
        .toList(growable: false);
    final radar = json['radar'];
    return CourseRatingDetail(
      course: course,
      teacher: teacher,
      average: _doubleValue(json['average']),
      total: intValue(json['total'], ratings.length),
      page: intValue(json['page'], 1),
      perPage: intValue(json['per_page'] ?? json['perPage'], ratings.length),
      ratings: ratings,
      radar: radar is JsonMap
          ? CourseRatingRadar.fromJson(radar)
          : const CourseRatingRadar(categories: [], values: []),
    );
  }
}

DateTime? _dateFromTimestamp(Object? value) {
  final raw = intValue(value);
  if (raw <= 0) {
    return null;
  }
  final milliseconds = raw > 1000000000000 ? raw : raw * 1000;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
      .toLocal();
}

double _doubleValue(Object? value, [double fallback = 0]) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}
