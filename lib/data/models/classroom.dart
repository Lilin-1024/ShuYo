import 'common.dart';

class ClassroomBuilding {
  const ClassroomBuilding({
    required this.id,
    required this.name,
    required this.campusId,
    required this.campusName,
    this.fullName = '',
    this.code = '',
  });

  final int id;
  final String name;
  final int campusId;
  final String campusName;
  final String fullName;
  final String code;

  JsonMap toJson() {
    return {
      'id': id,
      'name': name,
      'campusId': campusId,
      'campusName': campusName,
      'fullName': fullName,
      'code': code,
    };
  }

  factory ClassroomBuilding.fromJson(JsonMap json) {
    final campusId = intValue(json['campusId'] ?? json['parentNodeId']);
    final fullName = stringValue(json['fullName']);
    return ClassroomBuilding(
      id: intValue(json['id']),
      name: stringValue(json['name']),
      campusId: campusId,
      campusName: stringValue(
        json['campusName'],
        _campusNameFromFullName(fullName, campusId),
      ),
      fullName: fullName,
      code: stringValue(json['code'] ?? json['roomCode']),
    );
  }
}

class ClassroomSection {
  const ClassroomSection({
    required this.index,
    required this.startTime,
    required this.endTime,
  });

  final int index;
  final String startTime;
  final String endTime;

  String get label => '$index节 $startTime-$endTime';

  JsonMap toJson() {
    return {
      'index': index,
      'startTime': startTime,
      'endTime': endTime,
    };
  }

  factory ClassroomSection.fromJson(JsonMap json) {
    return ClassroomSection(
      index: intValue(json['index'] ?? json['sectionIndex']),
      startTime: stringValue(json['startTime']),
      endTime: stringValue(json['endTime']),
    );
  }
}

class ClassroomSearchOptions {
  const ClassroomSearchOptions({
    required this.buildings,
    required this.sections,
    this.currentSection = 0,
  });

  final List<ClassroomBuilding> buildings;
  final List<ClassroomSection> sections;
  final int currentSection;

  List<String> get campusNames {
    final names = <String>[];
    for (final building in buildings) {
      if (!names.contains(building.campusName)) {
        names.add(building.campusName);
      }
    }
    return names;
  }

  JsonMap toJson() {
    return {
      'buildings': buildings.map((building) => building.toJson()).toList(),
      'sections': sections.map((section) => section.toJson()).toList(),
      'currentSection': currentSection,
    };
  }

  factory ClassroomSearchOptions.fromJson(JsonMap json) {
    return ClassroomSearchOptions(
      buildings: (json['buildings'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(ClassroomBuilding.fromJson)
          .where((building) => building.id > 0 && building.name.isNotEmpty)
          .toList(growable: false),
      sections: (json['sections'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(ClassroomSection.fromJson)
          .where((section) => section.index > 0)
          .toList(growable: false),
      currentSection: intValue(json['currentSection']),
    );
  }
}

class ClassroomCourse {
  const ClassroomCourse({
    required this.courseName,
    required this.teacherName,
    required this.startSection,
    required this.endSection,
    this.source = '',
  });

  final String courseName;
  final String teacherName;
  final int startSection;
  final int endSection;
  final String source;

  String get sectionText => '$startSection-$endSection节';

  bool overlaps(int start, int end) {
    return startSection <= end && endSection >= start;
  }

  factory ClassroomCourse.fromJson(JsonMap json) {
    return ClassroomCourse(
      courseName: stringValue(json['courseName']),
      teacherName: stringValue(json['teacherName']),
      startSection: intValue(json['startSection']),
      endSection: intValue(json['endSection']),
      source: stringValue(json['sjly']),
    );
  }
}

class ClassroomRoom {
  const ClassroomRoom({
    required this.id,
    required this.name,
    required this.floorName,
    required this.fullName,
    required this.courses,
  });

  final int id;
  final String name;
  final String floorName;
  final String fullName;
  final List<ClassroomCourse> courses;

  bool isFreeFor(int startSection, int endSection) {
    return courses
        .every((course) => !course.overlaps(startSection, endSection));
  }

  List<ClassroomCourse> coursesFor(int startSection, int endSection) {
    return courses
        .where((course) => course.overlaps(startSection, endSection))
        .toList(growable: false);
  }

  factory ClassroomRoom.fromJson(JsonMap json, {required String floorName}) {
    return ClassroomRoom(
      id: intValue(json['id']),
      name: stringValue(json['name'] ?? json['text']),
      floorName: floorName,
      fullName: stringValue(json['fullName']),
      courses: (json['roomCourseList'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(ClassroomCourse.fromJson)
          .where((course) =>
              course.startSection > 0 &&
              course.endSection >= course.startSection)
          .toList(growable: false),
    );
  }
}

class ClassroomFloor {
  const ClassroomFloor({
    required this.id,
    required this.name,
    required this.rooms,
  });

  final int id;
  final String name;
  final List<ClassroomRoom> rooms;

  factory ClassroomFloor.fromJson(JsonMap json) {
    final name = stringValue(json['name'] ?? json['text']);
    return ClassroomFloor(
      id: intValue(json['id']),
      name: name,
      rooms: (json['children'] as List? ?? const [])
          .whereType<JsonMap>()
          .map((room) => ClassroomRoom.fromJson(room, floorName: name))
          .where((room) => room.id > 0 && room.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ClassroomBuildingSchedule {
  const ClassroomBuildingSchedule({
    required this.building,
    required this.floors,
  });

  final ClassroomBuilding building;
  final List<ClassroomFloor> floors;

  Iterable<ClassroomRoom> get rooms sync* {
    for (final floor in floors) {
      yield* floor.rooms;
    }
  }
}

class ClassroomAvailabilityResult {
  const ClassroomAvailabilityResult({
    required this.building,
    required this.date,
    required this.startSection,
    required this.endSection,
    required this.floors,
  });

  final ClassroomBuilding building;
  final DateTime date;
  final int startSection;
  final int endSection;
  final List<ClassroomFloorAvailability> floors;

  int get totalRooms => floors.fold(0, (sum, floor) => sum + floor.totalRooms);

  int get availableCount =>
      floors.fold(0, (sum, floor) => sum + floor.availableRooms.length);

  List<CourseLocationMatch> courseMatches(String keyword) {
    final normalized = keyword.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const <CourseLocationMatch>[];
    }
    final matches = <CourseLocationMatch>[];
    for (final floor in floors) {
      for (final room in floor.rooms) {
        for (final course in room.courses) {
          final haystack =
              '${course.courseName} ${course.teacherName} ${room.name}'
                  .toLowerCase();
          if (haystack.contains(normalized)) {
            matches.add(CourseLocationMatch(room: room, course: course));
          }
        }
      }
    }
    return matches;
  }
}

class ClassroomFloorAvailability {
  const ClassroomFloorAvailability({
    required this.floor,
    required this.rooms,
    required this.availableRooms,
  });

  final ClassroomFloor floor;
  final List<ClassroomRoom> rooms;
  final List<ClassroomRoom> availableRooms;

  int get totalRooms => rooms.length;
}

class CourseLocationMatch {
  const CourseLocationMatch({
    required this.room,
    required this.course,
  });

  final ClassroomRoom room;
  final ClassroomCourse course;
}

String _campusNameFromFullName(String fullName, int campusId) {
  final parts = fullName.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length >= 2) {
    return parts[1].replaceAll('校区', '');
  }
  return switch (campusId) {
    3 => '宝山',
    398 => '延长',
    475 => '宝山东区',
    574 => '嘉定',
    _ => '其它',
  };
}
