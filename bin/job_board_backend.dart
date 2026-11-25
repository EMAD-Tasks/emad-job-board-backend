import 'dart:convert';
import 'dart:io';

import 'package:emad_job_board_backend/models/canditatura.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import 'package:emad_job_board_backend/models/annuncio.dart';
import 'package:emad_job_board_backend/models/azienda.dart';
import 'package:emad_job_board_backend/storage/database_service.dart';

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};
const _uuid = Uuid();

Response _jsonResponse(int statusCode, Object body) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: _jsonHeaders,
  );
}

/// Middleware CORS utile se testi Flutter anche su Web o desktop
Middleware _corsMiddleware() {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept',
  };

  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: corsHeaders);
      }
      final response = await innerHandler(request);
      return response.change(headers: corsHeaders);
    };
  };
}

void main(List<String> args) async {
  final db = DatabaseService();
  await db.init();

  final router = Router();

  // REGISTRAZIONE AZIENDA (POST /register)
  router.post('/register', (Request request) async {
    final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final email = (payload['email'] as String? ?? '').trim().toLowerCase();
    final password = (payload['password'] as String? ?? '').trim();
    final nome = (payload['nome'] as String? ?? '').trim();

    if (email.isEmpty || password.isEmpty) {
      return _jsonResponse(400, {'error': 'Email e password sono obbligatorie'});
    }

    final esisteGia = db.aziende.any((a) => a.email.toLowerCase() == email);
    if (esisteGia) {
      return _jsonResponse(409, {'error': 'Email già registrata'});
    }

    final nuovaAzienda = Azienda(
      id: _uuid.v4(),
      nome: nome.trim(),
      email: email,
      password: password,
    );

    db.aziende.add(nuovaAzienda);
    await db.save();

    // Non restituiamo la password al client
    return _jsonResponse(201, {
      'id': nuovaAzienda.id,
      'nome': nuovaAzienda.nome,
      'email': nuovaAzienda.email,
    });
  });

  // LOGIN AZIENDA (POST /login)
  router.post('/login', (Request request) async {
    final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final email = (payload['email'] as String? ?? '').trim().toLowerCase();
    final password = (payload['password'] as String? ?? '').trim();

    final match = db.aziende.where(
      (a) => a.email.toLowerCase() == email && a.password == password,
    );

    if (match.isEmpty) {
      return _jsonResponse(401, {'error': 'Credenziali non valide'});
    }

    final azienda = match.first;
    return _jsonResponse(200, {
      'id': azienda.id,
      'nome': azienda.nome,
      'email': azienda.email,
    });
  });

  // LISTA ANNUNCI (GET /annunci oppure GET /annunci?aziendaId=...)
  router.get('/annunci', (Request request) {
    final aziendaId = request.url.queryParameters['aziendaId'];

    final risultati = (aziendaId != null && aziendaId.isNotEmpty)
        ? db.annunci.where((a) => a.aziendaId == aziendaId).toList()
        : db.annunci;

    // Restituiamo i più recenti per primi
    final ordinati = risultati.reversed.map((a) => a.toJson()).toList();
    return _jsonResponse(200, ordinati);
  });

  // PUBBLICA NUOVO ANNUNCIO (POST /annunci)
  router.post('/annunci', (Request request) async {
    final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final aziendaId = (payload['aziendaId'] as String? ?? '').trim();
    final titolo = (payload['titolo'] as String? ?? '').trim();
    final descrizione = (payload['descrizione'] as String? ?? '').trim();
    final ral = payload['ral'] as int?;

    if (aziendaId.isEmpty || titolo.isEmpty || descrizione.isEmpty) {
      return _jsonResponse(400, {'error': 'Campi obbligatori mancanti'});
    }

    final aziendeMatch = db.aziende.where((a) => a.id == aziendaId);
    if (aziendeMatch.isEmpty) {
      return _jsonResponse(404, {'error': 'Azienda non trovata'});
    }

    final nuovoAnnuncio = Annuncio(
      id: _uuid.v4(),
      aziendaId: aziendaId,
      aziendaNome: aziendeMatch.first.nome,
      titolo: titolo,
      descrizione: descrizione,
      ral: ral,
    );

    db.annunci.add(nuovoAnnuncio);
    await db.save();

    return _jsonResponse(201, nuovoAnnuncio.toJson());
  });

  // INVIA CANDIDATURA CON CV IN BASE64 (POST /candidature)
  router.post('/candidature', (Request request) async {
    final payload = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final annuncioId = (payload['annuncioId'] as String? ?? '').trim();
    final nome = (payload['nome'] as String? ?? '').trim();
    final cognome = (payload['cognome'] as String? ?? '').trim();
    final email = (payload['email'] as String? ?? '').trim();
    final cvBase64 = (payload['cvBase64'] as String? ?? '').trim();

    if (annuncioId.isEmpty ||
        nome.isEmpty ||
        cognome.isEmpty ||
        email.isEmpty ||
        cvBase64.isEmpty) {
      return _jsonResponse(400, {'error': 'Tutti i campi e il CV sono obbligatori'});
    }

    final annuncioEsiste = db.annunci.any((a) => a.id == annuncioId);
    if (!annuncioEsiste) {
      return _jsonResponse(404, {'error': 'Annuncio non trovato'});
    }

    final candidaturaId = _uuid.v4();
    final cvBytes = base64Decode(cvBase64);
    final savedFileName = await db.saveCvFile(candidaturaId, cvBytes);

    final nuovaCandidatura = Candidatura(
      id: candidaturaId,
      annuncioId: annuncioId,
      nome: nome,
      cognome: cognome,
      email: email,
      cvFileName: savedFileName,
    );

    db.candidature.add(nuovaCandidatura);
    await db.save();

    return _jsonResponse(201, nuovaCandidatura.toJson());
  });

  // CANDIDATURE PER UN SINGOLO ANNUNCIO (GET /annunci/<id>/candidature)
  router.get('/annunci/<id>/candidature', (Request request, String id) {
    final lista = db.candidature
        .where((c) => c.annuncioId == id)
        .map((c) => c.toJson())
        .toList();

    return _jsonResponse(200, lista);
  });

  // DOWNLOAD PDF DEL CURRICULUM (GET /uploads/<fileName>)
  router.get('/uploads/<fileName>', (Request request, String fileName) async {
    final file = db.getCvFile(fileName);
    if (file == null) {
      return _jsonResponse(404, {'error': 'File CV non trovato'});
    }

    final bytes = await file.readAsBytes();
    return Response.ok(
      bytes,
      headers: {
        'Content-Type': 'application/pdf',
        'Content-Disposition': 'inline; filename="$fileName"',
      },
    );
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  // InternetAddress.anyIPv4 permette connessioni sia da localhost sia dallo smartphone in Wi-Fi
  final server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
  print('Server avviato su http://${server.address.host}:${server.port}');
}