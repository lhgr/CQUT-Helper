class ScheduleData {
  String? yearTerm;
  String? weekNum;
  String? nowMonth;
  List<String>? yearTermList;
  List<String>? weekList;
  List<WeekDayItem>? weekDayList;
  List<EventItem>? eventList;

  ScheduleData({
    this.yearTerm,
    this.weekNum,
    this.nowMonth,
    this.yearTermList,
    this.weekList,
    this.weekDayList,
    this.eventList,
  });

  factory ScheduleData.fromJson(Map<String, dynamic> json) {
    return ScheduleData(
      yearTerm: json['yearTerm'],
      weekNum: json['weekNum'],
      nowMonth: json['nowMonth'],
      yearTermList: json['yearTermList'] != null
          ? List<String>.from(json['yearTermList'])
          : null,
      weekList: json['weekList'] != null
          ? List<String>.from(json['weekList'])
          : null,
      weekDayList: json['weekDayList'] != null
          ? (json['weekDayList'] as List)
                .map((e) => WeekDayItem.fromJson(e))
                .toList()
          : null,
      eventList: json['eventList'] != null
          ? (json['eventList'] as List)
                .map((e) => EventItem.fromJson(e))
                .toList()
          : null,
    );
  }

  ScheduleData copyWith({List<EventItem>? eventList}) {
    return ScheduleData(
      yearTerm: yearTerm,
      weekNum: weekNum,
      nowMonth: nowMonth,
      yearTermList: yearTermList == null
          ? null
          : List<String>.from(yearTermList!),
      weekList: weekList == null ? null : List<String>.from(weekList!),
      weekDayList: weekDayList == null
          ? null
          : List<WeekDayItem>.from(weekDayList!),
      eventList:
          eventList ??
          (this.eventList == null
              ? null
              : List<EventItem>.from(this.eventList!)),
    );
  }

  Map<String, dynamic> toJson() => {
    'yearTerm': yearTerm,
    'weekNum': weekNum,
    'nowMonth': nowMonth,
    'yearTermList': yearTermList,
    'weekList': weekList,
    'weekDayList': weekDayList?.map((e) => e.toJson()).toList(),
    'eventList': eventList?.map((e) => e.toJson()).toList(),
  };
}

class WeekDayItem {
  String? weekDay;
  String? weekDate;
  bool? today;

  WeekDayItem({this.weekDay, this.weekDate, this.today});

  factory WeekDayItem.fromJson(Map<String, dynamic> json) {
    return WeekDayItem(
      weekDay: json['weekDay'],
      weekDate: json['weekDate'],
      today: json['today'],
    );
  }

  Map<String, dynamic> toJson() => {
    'weekDay': weekDay,
    'weekDate': weekDate,
    'today': today,
  };
}

class EventItem {
  String? weekNum;
  String? weekDay;
  List<String>? weekList;
  String? weekCover;
  List<String>? sessionList;
  String? sessionStart;
  String? sessionLast;
  String? eventName;
  String? address;
  String? memberName;
  String? duplicateGroupType;
  int? duplicateGroup;
  String? eventType;
  String? eventID;
  String? note;
  int? reminderMinutes;
  int? colorIndex;
  String? customizationKey;

  EventItem({
    this.weekNum,
    this.weekDay,
    this.weekList,
    this.weekCover,
    this.sessionList,
    this.sessionStart,
    this.sessionLast,
    this.eventName,
    this.address,
    this.memberName,
    this.duplicateGroupType,
    this.duplicateGroup,
    this.eventType,
    this.eventID,
    this.note,
    this.reminderMinutes,
    this.colorIndex,
    this.customizationKey,
  });

  bool get isSchoolCustomCourse =>
      (eventType ?? '').trim() == '3' && (eventID ?? '').trim().isNotEmpty;

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(
      weekNum: json['weekNum'],
      weekDay: json['weekDay'],
      weekList: json['weekList'] != null
          ? List<String>.from(json['weekList'])
          : null,
      weekCover: json['weekCover'],
      sessionList: json['sessionList'] != null
          ? List<String>.from(json['sessionList'])
          : null,
      sessionStart: json['sessionStart'],
      sessionLast: json['sessionLast'],
      eventName: json['eventName'],
      address: json['address'],
      memberName: json['memberName'],
      duplicateGroupType: json['duplicateGroupType'],
      duplicateGroup: json['duplicateGroup'],
      eventType: json['eventType'],
      eventID: json['eventID'],
      note: json['note'],
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt(),
      colorIndex: (json['colorIndex'] as num?)?.toInt(),
      customizationKey: json['customizationKey'],
    );
  }

  EventItem copyWith({
    String? eventName,
    String? address,
    String? memberName,
    String? note,
    int? reminderMinutes,
    int? colorIndex,
    String? customizationKey,
  }) {
    return EventItem(
      weekNum: weekNum,
      weekDay: weekDay,
      weekList: weekList == null ? null : List<String>.from(weekList!),
      weekCover: weekCover,
      sessionList: sessionList == null ? null : List<String>.from(sessionList!),
      sessionStart: sessionStart,
      sessionLast: sessionLast,
      eventName: eventName ?? this.eventName,
      address: address ?? this.address,
      memberName: memberName ?? this.memberName,
      duplicateGroupType: duplicateGroupType,
      duplicateGroup: duplicateGroup,
      eventType: eventType,
      eventID: eventID,
      note: note ?? this.note,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      colorIndex: colorIndex ?? this.colorIndex,
      customizationKey: customizationKey ?? this.customizationKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'weekNum': weekNum,
    'weekDay': weekDay,
    'weekList': weekList,
    'weekCover': weekCover,
    'sessionList': sessionList,
    'sessionStart': sessionStart,
    'sessionLast': sessionLast,
    'eventName': eventName,
    'address': address,
    'memberName': memberName,
    'duplicateGroupType': duplicateGroupType,
    'duplicateGroup': duplicateGroup,
    'eventType': eventType,
    'eventID': eventID,
    if (note != null) 'note': note,
    if (reminderMinutes != null) 'reminderMinutes': reminderMinutes,
    if (colorIndex != null) 'colorIndex': colorIndex,
    if (customizationKey != null) 'customizationKey': customizationKey,
  };
}

class CampusTimeInfo {
  String? campusName;
  int? sessionNum;
  String? startTime;
  String? endTime;

  CampusTimeInfo({
    this.campusName,
    this.sessionNum,
    this.startTime,
    this.endTime,
  });

  factory CampusTimeInfo.fromJson(Map<String, dynamic> json) {
    return CampusTimeInfo(
      campusName: json['campusName'],
      sessionNum: json['sessionNum'],
      startTime: json['startTime'],
      endTime: json['endTime'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'campusName': campusName,
      'sessionNum': sessionNum,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}
