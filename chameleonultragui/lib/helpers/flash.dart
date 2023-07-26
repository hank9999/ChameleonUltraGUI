import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:chameleonultragui/comms/serial_abstract.dart';
import 'package:chameleonultragui/connector/chameleon.dart';
import 'package:chameleonultragui/connector/dfu.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';

Future<Uint8List> fetchFirmware(ChameleonDevice device) async {
  Uint8List content = Uint8List(0);

  final releases = json.decode((await http.get(Uri.parse(
          "https://api.github.com/repos/RfidResearchGroup/ChameleonUltra/releases")))
      .body
      .toString());

  for (var file in releases[0]["assets"]) {
    if (file["name"] ==
        "${(device == ChameleonDevice.ultra) ? "ultra" : "lite"}-dfu-app.zip") {
      content = await http.readBytes(Uri.parse(file["browser_download_url"]));
      break;
    }
  }

  return content;
}

Future<(Uint8List, Uint8List)> unpackFirmware(Uint8List content) async {
  Uint8List applicationDat = Uint8List(0);
  Uint8List applicationBin = Uint8List(0);

  final archive = ZipDecoder().decodeBytes(content);

  for (var file in archive.files) {
    if (file.isFile) {
      if (file.name == "application.dat") {
        applicationDat = file.content;
      } else if (file.name == "application.bin") {
        applicationBin = file.content;
      }
    }
  }

  return (applicationDat, applicationBin);
}

Future<void> flashFile(
    ChameleonCom? connection,
    MyAppState appState,
    Uint8List applicationDat,
    Uint8List applicationBin,
    void Function(int progress) callback,
    {bool enterDFU = true}) async {
  if (applicationDat.isEmpty || applicationBin.isEmpty) {
    throw ("Empty firmware file");
  }

  if (enterDFU) {
    await connection!.enterDFUMode();
    await appState.chameleon.performDisconnect();
  }

  List chameleons = [];

  while (chameleons.isEmpty) {
    await asyncSleep(250);
    chameleons = await appState.chameleon.availableChameleons(true);
  }

  if (chameleons.length > 1) {
    throw ("More than one Chameleon in DFU. Please connect only one at a time");
  }

  await appState.chameleon.connectSpecific(chameleons[0]['port']);
  var dfu = ChameleonDFU(port: appState.chameleon);
  await dfu.setPRN();
  await dfu.getMTU();
  await dfu.flashFirmware(0x01, applicationDat, callback);
  await dfu.flashFirmware(0x02, applicationBin, callback);
  appState.log.i("Firmware flashed!");
  appState.chameleon.performDisconnect();
  appState.changesMade();
}