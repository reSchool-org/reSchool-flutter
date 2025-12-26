class Account {
  final String username;
  final String password;
  final String fullName;
  final int? prsId;
  final int? imageId;
  String? sessionCookie;
  String? cloudToken;
  int? serverThreadId;
  bool isCloudEnabled;

  Account({
    required this.username,
    required this.password,
    required this.fullName,
    this.prsId,
    this.imageId,
    this.sessionCookie,
    this.cloudToken,
    this.serverThreadId,
    this.isCloudEnabled = false,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      username: json['username'],
      password: json['password'],
      fullName: json['fullName'],
      prsId: json['prsId'],
      imageId: json['imageId'],
      sessionCookie: json['sessionCookie'],
      cloudToken: json['cloudToken'],
      serverThreadId: json['serverThreadId'],
      isCloudEnabled: json['isCloudEnabled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'fullName': fullName,
      'prsId': prsId,
      'imageId': imageId,
      'sessionCookie': sessionCookie,
      'cloudToken': cloudToken,
      'serverThreadId': serverThreadId,
      'isCloudEnabled': isCloudEnabled,
    };
  }
}