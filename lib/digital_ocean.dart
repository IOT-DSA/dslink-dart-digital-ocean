library digital_ocean;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:redstone_mapper/mapper_factory.dart";
import "package:redstone_mapper/mapper.dart" as mapper;
import "package:redstone_mapper/mapper.dart" show Field;

class DigitalOcean {
  final String token;
  final Uri endpointUri;

  HttpClient _client = new HttpClient();

  factory DigitalOcean(String token, {String endpoint: "https://api.digitalocean.com/v2/"}) {
    var uri = Uri.parse(endpoint);
    bootstrapMapper();
    return new DigitalOcean._(token, uri);
  }

  DigitalOcean._(this.token, this.endpointUri);

  Future<HttpClientResponse> sendRequest(String method, String path, {
    Map<String, dynamic> headers,
    data
  }) async {
    var uri = endpointUri.resolve(path);
    var query = {};
    if (uri.queryParameters != null) {
      query.addAll(uri.queryParameters);
    }

    if (headers == null) {
      headers = {};
    }

    headers["Authorization"] = "Bearer ${token}";

    if (method == "GET" && data != null && data is Map) {
      for (var key in data.keys) {
        query[key.toString()] = data[key].toString();
      }
    }

    if (query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    HttpClientResponse response;

    var request = await _client.openUrl(method, uri);

    for (var key in headers.keys) {
      request.headers.set(key, headers[key].toString());
    }

    if (data is String) {
      request.write(data);
      response = await request.close();
    } else if (data is Uint8List) {
      request.add(data);
      response = await request.close();
    } else if (data is Stream) {
      await request.addStream(data);
    } else if (data == null) {
      response = await request.close();
    } else {
      request.headers.contentType = ContentType.JSON;
      request.write(const JsonEncoder().convert(data));
      response = await request.close();
    }

    return response;
  }

  Future<DigitalOceanResponse> fetchObject(String method, String path, {
    Map<String, dynamic> headers,
    data,
    bool stream: false,
    bool binary: false
  }) async {
    var response = await sendRequest(method, path, headers: headers, data: data);
    var obj = new DigitalOceanResponse(response);
    if (!stream) {
      if (binary) {
        obj.bytes = await response.fold([], (List<int> a, List<int> b) => a..addAll(b));
      } else {
        var string = await response.transform(const Utf8Decoder()).join();
        if (response.headers.contentType.mimeType == "application/json") {
          obj.json = const JsonDecoder().convert(string);
        } else {
          obj.string = string;
        }
      }
    } else {
      obj.stream = response;
    }
    return obj;
  }

  Future<Account> getAccountInfo() async {
    var response = await fetchObject("GET", "account");
    response.check();
    return response.getObject(Account, "account");
  }

  Future<List<Droplet>> getAllDroplets() async {
    var response = await fetchObject("GET", "droplets");
    response.check();
    return response.getObject(new TypeAssist<List<Droplet>>().type, "droplets");
  }

  Future<List<DropletImage>> getAllImages() async {
    var response = await fetchObject("GET", "images");
    response.check();
    return response.getObject(new TypeAssist<List<DropletImage>>().type, "images");
  }

  Future<Droplet> getDroplet(int id) async {
    var response = await fetchObject("GET", "droplet/${id}");
    response.check();
    return response.getObject(Droplet, "droplet");
  }

  Future<Droplet> createDroplet(
      String name,
      String region,
      String size,
      image,
      {
        List<dynamic> sshKeys,
        bool backups: false,
        bool ipv6: false,
        bool privateNetworking: false,
        String userData
      }) async {
    var map = {
      "name": name,
      "region": region,
      "size": size,
      "image": image,
      "backups": backups,
      "ipv6": ipv6,
      "private_networking": privateNetworking
    };

    if (image is DropletImage) {
      image = image.id;
    }

    if (sshKeys != null) {
      map["ssh_keys"] = sshKeys;
    }

    if (userData != null) {
      map["user_data"] = userData;
    }

    var response = await fetchObject("POST", "droplets", data: map);
    response.check();
    return response.getObject(Droplet, "droplet");
  }

  Future<DigitalOceanResponse> deleteDroplet(int id) async {
    var response = await fetchObject("DELETE", "droplets/${id}");
    response.check();
    return response;
  }

  void close() {
    _client.close(force: true);
  }

  Future<List<Region>> getRegions() async {
    var response = await fetchObject("GET", "regions");
    response.check();
    return response.getObject(new TypeAssist<List<Region>>().type, "regions");
  }

  Future<List<DropletSize>> getSizes() async {
    var response = await fetchObject("GET", "sizes");
    response.check();
    return response.getObject(new TypeAssist<List<DropletSize>>().type, "sizes");
  }

  Future<Action> sendDropletAction(int dropletId, String type, {Map extras}) async {
    var data = {
      "type": type
    };

    if (extras != null) {
      data.addAll(extras);
    }

    var response = await fetchObject("POST", "droplets/${dropletId}/actions", data: data);
    response.check();
    return response.getObject(Action, "action");
  }

  Future<Action> powerOnDroplet(int dropletId) async {
    return await sendDropletAction(dropletId, "power_on");
  }

  Future<Action> powerOffDroplet(int dropletId) async {
    return await sendDropletAction(dropletId, "power_off");
  }

  Future<Action> rebootDroplet(int dropletId) async {
    return await sendDropletAction(dropletId, "reboot");
  }
}

class TypeAssist<T> {
  Type get type => T;
}

class DigitalOceanResponse {
  final HttpClientResponse response;

  List<int> bytes;
  String string;
  Map<String, dynamic> json;
  Stream<List<int>> stream;

  DigitalOceanResponse(this.response);

  bool get isSuccess => response.statusCode >= 200 && response.statusCode < 300;

  void check() {
    if (!isSuccess) {
      throw new DigitalOceanError(this);
    }
  }

  dynamic getObject(Type type, [String drilldown]) {
    var j = json;
    if (drilldown != null) {
      j = json[drilldown];
    }
    var obj = mapper.decode(j, type);
    if (obj is DigitalOceanObject) {
      obj.response = this;
    }

    if (obj is List && obj.every((x) => x is DigitalOceanObject)) {
      for (var e in obj) {
        e.response = this;
      }
    }

    return obj;
  }
}

class DigitalOceanObject {
  DigitalOceanResponse response;

  Map asJSON() => mapper.encode(this);
}

class DigitalOceanError {
  final DigitalOceanResponse response;

  DigitalOceanError(this.response);

  @override
  String toString() {
    var msg = "Status Code: ${response.response.statusCode}";
    if (response.json["id"] != null) {
      msg += ", Error ID: ${response.json['id']}";
    }

    if (response.json["message"] != null) {
      msg += ", Message: ${response.json['message']}";
    }
    return msg;
  }
}

class Droplet extends DigitalOceanObject {
  @Field()
  int id;
  @Field()
  String name;
  @Field()
  num memory;
  @Field()
  int vcpus;
  @Field()
  num disk;

  @Field()
  bool locked;

  bool get isLocked => locked;

  @Field()
  String created_at;
  DateTime get createdAt => DateTime.parse(created_at);

  @Field()
  String status;
  @Field()
  List<int> backup_ids;
  List<int> get backupIds => backup_ids;

  @Field()
  List<String> features;

  @Field()
  List<int> snapshot_ids;
  List<int> get snapshotIds => snapshot_ids;

  @Field()
  Region region;

  @Field()
  String size_slug;
  String get sizeSlug => size_slug;

  @Field()
  DropletNetworks networks;
}

class Account extends DigitalOceanObject {
  @Field()
  int droplet_limit;
  int get dropletLimit => droplet_limit;

  @Field()
  String email;
  @Field()
  String uuid;

  @Field()
  bool email_verified;
  bool get isEmailVerified => email_verified;

  @Field()
  String status;

  @Field()
  String status_message;
  String get statusMessage => status_message;
}

class Region extends DigitalOceanObject {
  @Field()
  String slug;
  @Field()
  String name;
  @Field()
  List<String> sizes;
  @Field()
  List<String> features;
  @Field()
  bool available;

  bool get isAvailable => available;
}

class DropletNetworks extends DigitalOceanObject {
  @Field()
  List<DropletNetwork> v4;
  @Field()
  List<DropletNetwork> v6;
}

class DropletNetwork extends DigitalOceanObject {
  @Field()
  String ip_address;
  String get address => ip_address;

  @Field()
  String netmask;

  @Field()
  String gateway;

  @Field()
  String type;
}

class Action extends DigitalOceanObject {
  @Field()
  int id;
  @Field()
  String status;
  @Field()
  DateTime started_at;
}

class DropletImage extends DigitalOceanObject {
  @Field()
  int id;
  @Field()
  String name;
  @Field()
  String distribution;
  @Field()
  String slug;

  @Field()
  bool public;
  bool get isPublic => public;

  @Field()
  List<String> regions;

  @Field()
  DateTime created_at;
  @Field()
  DateTime get createdAt => created_at;

  @Field()
  num min_disk_space;
  num get minimumDiskSpace => min_disk_space;
}

class DropletSize extends DigitalOceanObject {
  @Field()
  String slug;

  @Field()
  bool available;
  bool get isAvailable => available;

  @Field()
  List<String> regions;

  @Field()
  num transfer;

  @Field()
  num price_monthly;
  num get priceMonthly => price_monthly;

  @Field()
  num price_hourly;
  num get priceHourly => price_hourly;

  @Field()
  num memory;

  @Field()
  int vcpus;

  @Field()
  num disk;
}
