import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  Future<void> updateShift(String barista, String key, int value) async {
    final ref = db.collection('settings').doc('shifts');

    await ref.set({
      '$barista.$key': value
    }, SetOptions(merge: true));
  }

  Future<void> updatePref(String barista, String key, int value) async {
    final ref = db.collection('settings').doc('prefs');

    await ref.set({
      '$barista.$key': value
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot> shiftsStream() {
    return db.collection('settings').doc('shifts').snapshots();
  }

  Stream<DocumentSnapshot> prefsStream() {
    return db.collection('settings').doc('prefs').snapshots();
  }

  Stream<QuerySnapshot> logsStream() {
    return db.collection('logs')
        .orderBy('time', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> addLog(String text) async {
    await db.collection('logs').add({
      'text': text,
      'time': FieldValue.serverTimestamp(),
    });
  }
}
