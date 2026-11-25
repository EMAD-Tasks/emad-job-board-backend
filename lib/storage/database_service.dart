import 'dart:convert';
import 'dart:io';
import 'package:emad_job_board_backend/models/annuncio.dart';
import 'package:emad_job_board_backend/models/azienda.dart';
import 'package:emad_job_board_backend/models/canditatura.dart';

class DatabaseService {
  final File _dbFile;
  final Directory uploadsDir;

  List<Azienda> aziende = [];
  List<Annuncio> annunci = [];
  List<Candidatura> candidature = [];

  DatabaseService({
    String dbPath = 'db.json',
    String uploadsPath = 'uploads',
  })  : _dbFile = File(dbPath),
        uploadsDir = Directory(uploadsPath);

  /// Inizializza cartella uploads e carica i dati da db.json
  Future<void> init() async {
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }

    if (!await _dbFile.exists()) {
      await save();
      return;
    }

    final content = await _dbFile.readAsString();
    if (content.trim().isEmpty) {
      await save();
      return;
    }

    final Map<String, dynamic> data = jsonDecode(content);

    aziende = (data['aziende'] as List<dynamic>? ?? [])
        .map((e) => Azienda.fromJson(e as Map<String, dynamic>))
        .toList();

    annunci = (data['annunci'] as List<dynamic>? ?? [])
        .map((e) => Annuncio.fromJson(e as Map<String, dynamic>))
        .toList();

    candidature = (data['candidature'] as List<dynamic>? ?? [])
        .map((e) => Candidatura.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Salva lo stato corrente su db.json in formato leggibile
  Future<void> save() async {
    final data = {
      'aziende': aziende.map((e) => e.toJson()).toList(),
      'annunci': annunci.map((e) => e.toJson()).toList(),
      'candidature': candidature.map((e) => e.toJson()).toList(),
    };

    const encoder = JsonEncoder.withIndent('  ');
    await _dbFile.writeAsString(encoder.convert(data));
  }

  /// Salva i byte del CV nella cartella uploads/ e restituisce il nome file salvato
  Future<String> saveCvFile(String candidaturaId, List<int> bytes) async {
    final fileName = '$candidaturaId.pdf';
    final file = File('${uploadsDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return fileName;
  }

  /// Recupera il file CV dalla cartella uploads/ (null se non esiste)
  File? getCvFile(String fileName) {
    final safeName = Uri.file(fileName).pathSegments.last;
    final file = File('${uploadsDir.path}/$safeName');
    return file.existsSync() ? file : null;
  }
}