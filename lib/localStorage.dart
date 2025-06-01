import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LStorage {
  // Ajouter des données à SharedPreferences
  Future<void> addToLocalStorage(String key, String value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    print('Data added to local storage');
  }

  // Obtenir des données sous forme de Map depuis SharedPreferences
  Future<Map<String, dynamic>?> getMapFromLocalStorage(String key) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(key);
    if (jsonString != null) {
      return jsonDecode(jsonString);
    }
    return null;
  }

  // Charger des données depuis SharedPreferences pour 'factureData'
  Future<List<Map<String, dynamic>>> loadFromLocalStorage() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? jsonString = prefs.getString('factureData');
      if (jsonString != null) {
        List<dynamic> jsonDataList = jsonDecode(jsonString);
        return jsonDataList.cast<Map<String, dynamic>>();
      } else {
        print('No data found in local storage.');
        return [];
      }
    } catch (e) {
      print('Error loading data from local storage: $e');
      return [];
    }
  }

  // Charger des données uniques depuis SharedPreferences pour 'factureUniqueData'
  Future<List<Map<String, dynamic>>> loadUniqueFromLocalStorage() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? jsonString = prefs.getString('factureUniqueData');
      if (jsonString != null) {
        List<dynamic> jsonDataList = jsonDecode(jsonString);
        return jsonDataList.cast<Map<String, dynamic>>();
      } else {
        print('No data found in local storage.');
        return [];
      }
    } catch (e) {
      print('Error loading data from local storage: $e');
      return [];
    }
  }

  // Construire une liste de cartes à partir des données
  List<Widget> buildCards(List<Map<String, dynamic>> data) {
    return data.map((item) {
      return Card(
        child: ListTile(
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${item['LIBELLEARTICLE']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item['DATEFACT']}',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kilométrage actuel: ',
                style: TextStyle(color: Colors.blue, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                '${item['NbrKM'] * 1000} KM',
                style: const TextStyle(color: Colors.black, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'Prochain entretien: ',
                style: TextStyle(color: Colors.blue, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                '${item['NbrKM'] * 1000 + 100000} KM',
                style: const TextStyle(color: Colors.black, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // Obtenir des données stockées sous forme de Map
  Future<Map<String, dynamic>?> getStoredData(String key) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(key);
    if (jsonString != null) {
      return jsonDecode(jsonString);
    }
    return null;
  }
}

class UserData {
  final String Plate;
  final String Plate3;
  final String Plate4;
  final String UserName;
  final String Email;
  final String Tel;
  final String MatType;

  UserData({
    required this.Plate3,
    required this.MatType,
    required this.Plate4,
    required this.UserName,
    required this.Email,
    required this.Plate,
    required this.Tel,
  });
}

class UserMapper {
  static UserData mapToUserData(Map<String, dynamic> map) {
    return UserData(
      UserName: map['UserName'] ?? '',
      Email: map['Email'] ?? '',
      Plate: map['Plate'] ?? '',
      Plate3: map['Plate3'] ?? '',
      Plate4: map['Plate4'] ?? '',
      Tel: map['Tel'] ?? '',
      MatType: map['MatType'] ?? '',
    );
  }
}

class FactureData {
  final String Datefact;
  final String IMAT;
  final String LIBELLEARTICLE;
  final String NOM_CLIENT;
  final String NUMFACT;
  final int NbrKM;
  final String TypeMat;

  FactureData({
    required this.Datefact,
    required this.IMAT,
    required this.LIBELLEARTICLE,
    required this.NOM_CLIENT,
    required this.NUMFACT,
    required this.NbrKM,
    required this.TypeMat,
  });

  factory FactureData.fromJson(Map<String, dynamic> json) {
    return FactureData(
      Datefact: json['DATEFACT'],
      IMAT: json['IMAT'],
      LIBELLEARTICLE: json['LIBELLEARTICLE'],
      NOM_CLIENT: json['NOM_CLIENT'],
      NUMFACT: json['NUMFACT'],
      NbrKM: json['NbrKM'],
      TypeMat: json['TypeMat'],
    );
  }
}
