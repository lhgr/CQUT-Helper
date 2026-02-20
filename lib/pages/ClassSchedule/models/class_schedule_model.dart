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
  });

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
    );
  }
}
