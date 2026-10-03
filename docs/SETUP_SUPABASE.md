# Configurazione Supabase – progetto MILANAC

Progetto: `https://bxtnvgnxfyzwamfdnmkx.supabase.co`
**URL di callback** da usare in TUTTI i provider (Google, Microsoft, Yahoo, Apple):

```
https://bxtnvgnxfyzwamfdnmkx.supabase.co/auth/v1/callback
```

## 1. Database (5 minuti)
1. Dashboard Supabase → **SQL Editor** → *New query*
2. Incolla tutto il file `supabase/migrations/0001_schema_iniziale.sql` → **Run**
3. Deve comparire "Success. No rows returned".
4. Ripeti con `supabase/migrations/0002_limiti_media.sql` (limiti di dimensione dei file caricati)
   poi con `0003_forma_trofei.sql` (forma dei trofei dell'Albo d'oro)
   e infine con `0004_notifiche_e_account.sql` (notifiche push ed eliminazione account).

## 2. URL dell'app
**Authentication → URL Configuration → Redirect URLs** → *Add URL*:
```
com.milanacproclub.milanac://login-callback
```

## 3. Google
1. https://console.cloud.google.com → nuovo progetto "MILANAC"
2. *API e servizi → Schermata consenso OAuth* → Esterno, nome app "MILANAC Pro Club", la tua email
3. *Credenziali → Crea credenziali → ID client OAuth* → tipo **Applicazione web**
   - URI di reindirizzamento autorizzati: l'URL di callback sopra
4. Copia **Client ID** e **Client secret** → Supabase → *Authentication → Providers → Google* → abilita e incolla.

## 4. Microsoft (Hotmail / Outlook / Live)
1. https://portal.azure.com → **Microsoft Entra ID → Registrazioni app → Nuova registrazione**
   - Nome "MILANAC Pro Club"
   - Tipi di account: **Account in qualsiasi directory organizzativa e account Microsoft personali**
   - URI di reindirizzamento (Web): l'URL di callback sopra
2. *Certificati e segreti → Nuovo segreto client* → copia il **Valore**
3. Supabase → *Providers → Azure* → abilita: **Application (client) ID**, **Secret Value**,
   Azure Tenant URL: `https://login.microsoftonline.com/common`

## 5. Yahoo
1. https://developer.yahoo.com/apps/ → *Create an App*
   - Redirect URI: l'URL di callback sopra
   - API Permissions: **OpenID Connect Permissions** → Email, Profile
2. Supabase → *Authentication → Providers* → **Add custom provider** (OIDC)
   - Identificativo: `yahoo`  (l'app lo chiama `custom:yahoo`)
   - Issuer URL: `https://api.login.yahoo.com`
   - Client ID e Client Secret dell'app Yahoo
   - Scopes: `openid email profile`

## 6. Apple (obbligatorio per l'App Store)
1. https://developer.apple.com/account → *Certificates, IDs & Profiles*
   - **Identifiers → App IDs**: `com.milanacproclub.milanac`, abilita *Sign in with Apple*
   - **Identifiers → Services IDs**: es. `com.milanacproclub.milanac.signin`, abilita *Sign in with Apple*,
     Domain: `bxtnvgnxfyzwamfdnmkx.supabase.co`, Return URL: l'URL di callback sopra
   - **Keys**: nuova chiave con *Sign in with Apple* → scarica il file `.p8` (si scarica una sola volta!)
2. Supabase → *Providers → Apple* → abilita, inserisci Services ID e genera il secret
   seguendo le istruzioni del pannello (Team ID, Key ID, file .p8).
   ⚠️ Il secret Apple scade ogni 6 mesi: va rigenerato (promemoria nel calendario!).

## 7. Primo Direttivo
1. Apri l'app e fai login (finirai in "Account in attesa").
2. SQL Editor:
   ```sql
   select id, display_name, created_at from profiles order by created_at;
   update profiles set club_role = 'direttivo' where display_name = 'IL TUO NOME';
   ```
3. L'app si sblocca da sola. Da qui in poi gli altri li approva il Direttivo.

## 8. Notizie automatiche (GitHub Actions)
1. Su GitHub apri il repository **milanac-app** → **Settings → Secrets and variables → Actions**
2. **New repository secret**
   - Name: `SUPABASE_SECRET_KEY`
   - Secret: la chiave `sb_secret_…` (Supabase → Settings → API Keys)
3. Vai su **Actions → Notizie → Run workflow** per la prima raccolta.
   Nel log vedi, fonte per fonte, quante notizie sono arrivate (✓) o se è stata saltata (✗).
4. Da lì in poi parte da solo ogni 3 ore (alle :17).

> Nota: le esecuzioni programmate partono solo dal branch principale (`main`):
> il workflow si attiva da solo dopo il merge della pull request.

## Sicurezza
- La chiave **publishable** (`sb_publishable_…`) è nel repository: va bene, è pensata per stare nell'app.
- La chiave **secret** (`sb_secret_…`) NON va mai messa nell'app né nel repository:
  servirà solo come *secret* di GitHub Actions per il job delle notizie.
