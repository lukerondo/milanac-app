#!/usr/bin/env python3
"""Controlli di tools/db/auth_urls.py: si aggiunge soltanto, senza perdere né ripetere."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from auth_urls import WEB_APP_URLS, merged  # noqa: E402

APP = "com.milanacproclub.milanac://login-callback"

# L'indirizzo dell'app sul telefono resta, quelli della web app vanno in coda.
assert merged(APP, WEB_APP_URLS) == (",".join([APP, *WEB_APP_URLS]), WEB_APP_URLS)
# Elenco vuoto o mai impostato.
assert merged(None, WEB_APP_URLS) == (",".join(WEB_APP_URLS), WEB_APP_URLS)
assert merged("", ["x"]) == ("x", ["x"])
# Già presenti (anche con spazi): niente da fare, niente doppioni.
assert merged(f" {APP} , {WEB_APP_URLS[0]},{WEB_APP_URLS[1]} ", WEB_APP_URLS)[1] == []
# Ne manca uno solo.
assert merged(f"{APP},{WEB_APP_URLS[0]}", WEB_APP_URLS) == (
    ",".join([APP, *WEB_APP_URLS]),
    [WEB_APP_URLS[1]],
)
print("Redirect URLs: controlli OK")
