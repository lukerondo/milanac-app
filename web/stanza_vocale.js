// Stanza vocale nel browser: poche funzioni sopra l'SDK Web di Agora, la stessa rete delle
// app sul telefono (chi entra da qui parla con chi è entrato dall'app). L'app (Dart) chiama
// milanacVoce.entra() e riceve i comandi della stanza: vedi
// lib/features/voce/voice_engine_web.dart.
//
// L'SDK (agora-rtc-sdk-ng, licenza MIT) si scarica solo al primo ingresso in una stanza:
// lo mette accanto all'app tools/web/agora_sdk.sh, quando si compila.
(function () {
  'use strict';

  var SDK = 'agora/AgoraRTC_N-production.js';
  // Volume (0-100) sopra il quale qualcuno "sta parlando".
  var SOGLIA = 45;
  var caricamento = null;

  function caricaSdk() {
    if (window.AgoraRTC) return Promise.resolve(window.AgoraRTC);
    if (!caricamento) {
      caricamento = new Promise(function (ok, no) {
        var s = document.createElement('script');
        s.src = new URL(SDK, document.baseURI).href;
        s.async = true;
        s.onload = function () {
          if (!window.AgoraRTC) return no(new Error('SDK_MANCANTE'));
          var rtc = window.AgoraRTC;
          try {
            rtc.setLogLevel(3); // solo gli errori nella console
            rtc.disableLogUpload();
            // "Chi parla" ogni 300 ms, come sul telefono (di suo sarebbero 2 secondi).
            rtc.setParameter('AUDIO_VOLUME_INDICATION_INTERVAL', 300);
          } catch (e) { /* versioni future: i valori di serie vanno bene lo stesso */ }
          ok(rtc);
        };
        s.onerror = function () {
          // Rete assente o file mancante: al prossimo ingresso si riprova.
          caricamento = null;
          s.remove();
          no(new Error('SDK_MANCANTE'));
        };
        document.head.appendChild(s);
      });
    }
    return caricamento;
  }

  function sigla(e) {
    return String((e && (e.code || e.name || e.message)) || 'ERRORE');
  }

  // Entra nella stanza. Opzioni: appId, canale, token, uid (numero) e tre avvisi:
  //   parla(numeri utente di chi sta parlando), caduta(motivo), biglietto(è già scaduto?).
  // Restituisce subito i comandi; `pronto` si chiude con '' quando si è dentro, oppure
  // con la sigla dell'errore (e la stanza è già stata lasciata).
  function entra(o) {
    var client = null;
    var mic = null;
    var uscito = false;
    var dentro = false;

    async function chiudi() {
      try { if (mic) { mic.stop(); mic.close(); } } catch (e) { /* già chiuso */ }
      mic = null;
      try { if (client) { client.removeAllListeners(); await client.leave(); } } catch (e) { /* già fuori */ }
      client = null;
    }

    var pronto = (async function () {
      try {
        var rtc = await caricaSdk();
        if (uscito) return 'USCITO';
        if (!rtc.checkSystemRequirements()) return 'BROWSER_NON_ADATTO';
        client = rtc.createClient({ mode: 'rtc', codec: 'vp8' });
        client.on('user-published', async function (utente, tipo) {
          if (tipo !== 'audio') return;
          try {
            await client.subscribe(utente, tipo);
            if (!uscito && utente.audioTrack) utente.audioTrack.play();
          } catch (e) { /* uscito nel frattempo, o l'altro ha già richiuso il microfono */ }
        });
        client.on('volume-indicator', function (volumi) {
          var chi = [];
          for (var i = 0; i < volumi.length; i++) {
            if (volumi[i].level > SOGLIA) chi.push(Number(volumi[i].uid));
          }
          o.parla(chi);
        });
        client.on('connection-state-change', function (ora, prima, motivo) {
          if (ora === 'DISCONNECTED' && dentro && !uscito) o.caduta(String(motivo || ''));
        });
        client.on('token-privilege-will-expire', function () { o.biglietto(false); });
        client.on('token-privilege-did-expire', function () { o.biglietto(true); });

        // Prima il microfono: senza permesso o senza dispositivo non si entra nemmeno.
        mic = await rtc.createMicrophoneAudioTrack({ AEC: true, ANS: true, AGC: true });
        if (uscito) { await chiudi(); return 'USCITO'; }
        await client.join(o.appId, o.canale, o.token, o.uid);
        if (uscito) { await chiudi(); return 'USCITO'; }
        client.enableAudioVolumeIndicator();
        await client.publish([mic]);
        if (uscito) { await chiudi(); return 'USCITO'; }
        dentro = true;
        return '';
      } catch (e) {
        await chiudi();
        return sigla(e);
      }
    })();

    return {
      pronto: pronto,
      muto: async function (si) { if (mic) await mic.setMuted(!!si); },
      rinnova: async function (token) { if (client) await client.renewToken(token); },
      esci: async function () {
        if (uscito) return;
        uscito = true;
        // L'ingresso in corso si ferma al passo successivo e chiude da sé.
        await pronto;
        await chiudi();
      },
    };
  }

  window.milanacVoce = { entra: entra };
})();
