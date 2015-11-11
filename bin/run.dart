import "dart:async";

import "package:dslink/dslink.dart";
import "package:dslink_digital_ocean/digital_ocean.dart";

LinkProvider link;

class AccountNode extends SimpleNode {
  AccountNode(String path) : super(path);

  @override
  onCreated() async {
    String token = configs[r"$$token"];

    if (token == null) {
      remove();
      return;
    }

    link.addNode("${path}/droplets", {
      r"$name": "Droplets"
    });

    link.addNode("${path}/regions", {
      r"$name": "Regions"
    });

    link.addNode("${path}/droplets/create", {
      r"$is": "createDroplet",
      r"$name": "Create Droplet",
      r"$invokable": "write",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "region",
          "type": "string"
        },
        {
          "name": "size",
          "type": "string"
        },
        {
          "name": "image",
          "type": "string"
        },
        {
          "name": "ipv6",
          "type": "bool"
        }
      ],
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        },
        {
          "name": "message",
          "type": "string"
        }
      ]
    });

    ocean = new DigitalOcean(token);

    _timer = Scheduler.every(Interval.FIVE_SECONDS, () async {
      await update();
    });

    await update();
  }

  update() async {
    try {
      await _update();
    } catch (e) {
      updating = false;
    }
  }

  int counter = 0;

  _update() async {
    if (updating) {
      return;
    }
    updating = true;

    List<Droplet> droplets = await ocean.getAllDroplets();

    var dids = link.getNode("${path}/droplets").children.values
        .map((n) => n.configs[r"$droplet_id"])
        .where((x) => x != null)
        .toList();

    for (Droplet droplet in droplets) {
      dids.remove(droplet.id);
      String tp = "${path}/droplets/${droplet.id}";
      if (link.provider.getNode(tp) == null) {
        link.addNode(tp, {
          r"$name": droplet.name,
          r"$droplet_id": droplet.id,
          "id": {
            r"$name": "ID",
            r"$type": "int"
          },
          "name": {
            r"$name": "Name",
            r"$type": "string"
          },
          "size": {
            r"$name": "Size",
            r"$type": "string"
          },
          "status": {
            r"$name": "Status",
            r"$type": "string"
          },
          "disk": {
            r"$name": "Disk",
            r"$type": "number",
            "@unit": "GB"
          },
          "memory": {
            r"$name": "Memory",
            r"$type": "number",
            "@unit": "MB"
          },
          "region": {
            r"$name": "Region",
            r"$type": "string"
          },
          "ipv4": {
            r"$name": "IPv4",
            r"$type": "list"
          },
          "ipv6": {
            r"$name": "IPv6",
            r"$type": "list"
          },
          "power_on": {
            r"$name": "Power On",
            r"$invokable": "write",
            r"$result": "values",
            r"$is": "powerOnDroplet",
            r"$columns": [
              {
                "name": "success",
                "type": "bool"
              },
              {
                "name": "message",
                "type": "string"
              }
            ]
          },
          "power_off": {
            r"$name": "Power Off",
            r"$invokable": "write",
            r"$result": "values",
            r"$is": "powerOffDroplet",
            r"$columns": [
              {
                "name": "success",
                "type": "bool"
              },
              {
                "name": "message",
                "type": "string"
              }
            ]
          }
        });
      }

      SimpleNode node = link.getNode(tp);
      sv(String name, value) {
        var n = link.getNode("${node.path}/${name}");
        if (n != null) {
          n.updateValue(value);
        }
      }

      sv("id", droplet.id);
      sv("name", droplet.name);
      sv("size", droplet.sizeSlug);
      sv("status", droplet.status);
      sv("disk", droplet.disk);
      sv("memory", droplet.memory);
      sv("region", droplet.region.name);
      sv("ipv4", droplet.networks.v4.map((x) => x.address).toList());
      sv("ipv6", droplet.networks.v6.map((x) => x.address).toList());
    }

    for (var id in dids) {
      link.removeNode("${path}/droplets/${id}");
    }

    if ((counter % 2) == 0) {
      var regions = await ocean.getRegions();
      for (var region in regions) {
        var p = "${path}/regions/${region.slug}";
        if (link.getNode(p) == null) {
          link.addNode("${path}/regions/${region.slug}", {
            r"$name": region.name,
            "name": {
              r"$name": "Name",
              r"$type": "string"
            },
            "slug": {
              r"$name": "Slug",
              r"$type": "string"
            },
            "features": {
              r"$name": "Features",
              r"$type": "list"
            },
            "available": {
              r"$name": "Available",
              r"$type": "bool"
            },
            "sizes": {
              r"$name": "Sizes",
              r"$type": "list"
            }
          });
        }

        link.updateValue("${p}/name", region.name);
        link.updateValue("${p}/slug", region.slug);
        link.updateValue("${p}/features", region.features);
        link.updateValue("${p}/sizes", region.sizes);
        link.updateValue("${p}/available", region.isAvailable);
      }

      var names = regions.map((x) => x.slug).toList();

      var regionsNode = link.getNode("${path}/regions");

      for (var a in regionsNode.children.keys.toList()) {
        if (!names.contains(a)) {
          link.removeNode("${path}/regions/${a}");
        }
      }
    }

    counter++;

    if (counter >= 500) {
      counter = 0;
    }

    updating = false;
  }

  @override
  Map save() {
    return {
      r"$is": "account",
      r"$name": configs[r"$name"],
      r"$$token": configs[r"$$token"]
    };
  }

  bool updating = false;
  Timer _timer;
  DigitalOcean ocean;
}

class AddAccountNode extends SimpleNode {
  AddAccountNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params["name"];
    var token = params["token"];

    var map = {
      r"$name": name,
      r"$is": "account",
      r"$$token": token
    };

    var ocean = new DigitalOcean(token);

    Account account;

    try {
      account = await ocean.getAccountInfo().timeout(const Duration(seconds: 5));
    } catch (e) {
      return {
        "success": false,
        "message": "ERROR: ${e}"
      };
    }

    link.addNode("/${name}", map);

    link.save();

    return {
      "success": true,
      "message": "Success! Added account for ${account.email}"
    };
  }
}

class CreateDropletNode extends SimpleNode {
  CreateDropletNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var name = params["name"];
    var region = params["region"];
    var size = params["size"];
    var image = params["image"];
    var ipv6 = params["ipv6"];

    if (ipv6 == null) {
      ipv6 = false;
    }

    AccountNode account = link.getNode(new Path(path).parentPath);

    try {
      var ocean = account.ocean;
      var droplet = await ocean.createDroplet(
          name,
          region,
          size,
          image,
          ipv6: ipv6
      );
    } catch (e) {
      return {
        "success": false,
        "message": "ERROR: ${e}"
      };
    }

    return {
      "success": true,
      "message": "Success!"
    };
  }
}

main(List<String> args) async {
  link = new LinkProvider(args, "DigitalOcean-", nodes: {
    "add": {
      r"$is": "addAccount",
      r"$name": "Add Account",
      r"$result": "values",
      r"$invokable": "write",
      r"$params": [
        {
          "name": "name",
          "type": "string",
          "placeholder": "MyAccount"
        },
        {
          "name": "token",
          "type": "string",
          "placeholder": "MyToken"
        }
      ],
      r"$columns": [
        {
          "name": "success",
          "type": "bool"
        },
        {
          "name": "message",
          "type": "string"
        }
      ]
    }
  }, profiles: {
    "account": (String path) => new AccountNode(path),
    "addAccount": (String path) => new AddAccountNode(path),
    "createDroplet": (String path) => new CreateDropletNode(path),
    "powerOnDroplet": (String path) => new StartDropletNode(path),
    "powerOffDroplet": (String path) => new StopDropletNode(path)
  }, autoInitialize: false);

  link.init();
  link.connect();
}

class StartDropletNode extends SimpleNode {
  StartDropletNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var p = new Path(path);
    var name = p.parent.name;
    AccountNode account = link.getNode(p.parent.parent.parent.path);

    try {
      var ocean = account.ocean;
      var action = await ocean.powerOnDroplet(int.parse(name));
    } catch (e) {
      return {
        "success": false,
        "message": "ERROR: ${e}"
      };
    }

    return {
      "success": true,
      "message": "Success!"
    };
  }
}

class StopDropletNode extends SimpleNode {
  StopDropletNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) async {
    var p = new Path(path);
    var name = p.parent.name;
    AccountNode account = link.getNode(p.parent.parent.parent.path);

    try {
      var ocean = account.ocean;
      var action = await ocean.powerOffDroplet(int.parse(name));
    } catch (e) {
      return {
        "success": false,
        "message": "ERROR: ${e}"
      };
    }

    return {
      "success": true,
      "message": "Success!"
    };
  }
}

