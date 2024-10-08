import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drb_app/models/Activity.dart';
import 'package:drb_app/models/LotLocations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LotProvider extends ChangeNotifier {
  FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  List<LotLocation> _lots = [];
  List<LotLocation> _locatedLots = [];

  bool _stillSearching = true;

  List<String> _names = [];
  Future fetchLots() async {
    try {
      QuerySnapshot snap = await db.collection('Locations').get();
      _lots = [];
      _names = [];

      for (var doc in snap.docs) {
        final res = LotLocation.fromMap(doc.data() as Map);
        _lots.add(res);
        _names.add(res.name);
      }
      notifyListeners();
    } catch (e) {
      print(e);
    }
  }

  locateLots() async {
    _stillSearching = true;
    _locatedLots.clear();
    notifyListeners();

    var loc = await _determinePosition();
    await (fetchLots());

    for (var lot in _lots) {
      var a = Geolocator.distanceBetween(
          loc.latitude, loc.longitude, lot.lat, lot.long);
      if (a < 600) {
        _locatedLots.add(lot);
      }
    }
    if (_locatedLots.isEmpty) {
      _stillSearching = false;
    }
    notifyListeners();
  }

  Future<String> getSupervisorName() async {
    String uid = _firebaseAuth.currentUser!.uid;
    var doc = await db.collection("Users").doc(uid).get();
    return doc.data()!['Name'];
  }

  addLocation(LotLocation lot) async {
    await db
        .collection("Locations")
        .doc(lot.name)
        .set(lot.toJson())
        .onError((e, _) => print("Error writing document: $e"));

    notifyListeners();

    String address = lot.address.toString() +
        " " +
        lot.street +
        ', ' +
        lot.city +
        ', ' +
        lot.state +
        ' ' +
        lot.zip.toString();

    String sup = await getSupervisorName();

    Activity curAct = Activity(
        user: sup,
        activity: "Added Location: ${lot.name}, ${lot.number} at $address",
        when: DateTime.now());

    await db
        .collection("Activity")
        .doc()
        .set(curAct.toJson())
        .onError((e, _) => print("Error writing document: $e"));
  }

  List<LotLocation> get getlots {
    return _lots;
  }

  List<LotLocation> get getLocatedLots {
    return _locatedLots;
  }

  List<String> get getNames {
    return _names;
  }

  bool get stillSearching {
    return _stillSearching;
  }

  void notify() {
    notifyListeners();
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    var a = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return a;
  }
}
