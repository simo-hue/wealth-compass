# Guida all'Installazione

Segui questi passaggi per configurare Wealth Compass sulla tua macchina locale.

## Prerequisiti

Prima di iniziare, assicurati di avere installato:

- **Node.js**: v18 o superiore ([Scarica](https://nodejs.org/))
- **Git**: ([Scarica](https://git-scm.com/))
- **Account Supabase**: Per autenticazione e database ([Registrati](https://supabase.com/))
- **Chiave API Finnhub**: Chiave gratuita per i prezzi delle azioni ([Ottieni chiave](https://finnhub.io/))

## Istruzioni di Configurazione

### 1. Clona il Repository

```bash
git clone <URL_TUO_REPO>
cd wealth-compass/web-app
```

> La radice del repository contiene entrambe le piattaforme: `apple/` per le app native iOS e
> macOS, e `web-app/` per questa. Tutti i comandi seguenti vanno eseguiti da `web-app/`.

### 2. Installa le Dipendenze

```bash
npm install
```

### 3. Configura Supabase

1. Crea un nuovo progetto nella dashboard di Supabase.
2. Vai all'**Editor SQL** in Supabase ed esegui le query necessarie per impostare lo schema del database (assicurati che esistano le tabelle `assets`, `liabilities`, `liquidity_accounts`, `portfolio_snapshots`, `transactions` e `profiles`).
3. Abilita l'**Autenticazione** (Email/Password) nelle impostazioni di Supabase. L'app effettua il login solo tramite email e password; non esiste un flusso Magic Link / OTP.

### 4. Variabili d'Ambiente

Crea un file `.env` in questa directory `web-app/` (accanto a `package.json`) copiando `env_example.txt`, o creandone uno nuovo.

```bash
touch .env
```

Aggiungi le seguenti variabili al tuo file `.env`:

```env
# Configurazione Supabase (Richiesto per Auth e DB)
VITE_SUPABASE_URL=url_tuo_progetto_supabase
VITE_SUPABASE_ANON_KEY=chiave_anon_tuo_progetto_supabase

# API Dati Finanziari
VITE_FINNHUB_API_KEY=tua_chiave_api_finnhub
```

> **Nota**: Puoi trovare l'URL e la Chiave Anon di Supabase nelle Impostazioni del Progetto > API.

### 5. Avvia l'Applicazione

Avvia il server di sviluppo:

```bash
npm run dev
```

Apri il browser e vai su `http://localhost:8080` (o alla porta mostrata nel terminale).

## Build per la Produzione

Per creare una build ottimizzata per la produzione:

```bash
npm run build
```

I file generati si troveranno nella cartella `dist`. Il progetto è configurato per il deploy su **GitHub Pages** nel sotto-percorso `/wealth-compass/` — esegui `npm run deploy` (compila e pubblica `dist` tramite `gh-pages`). Il `base` di Vite (`vite.config.ts`) e il `basename` di React Router (`src/App.tsx`) sono entrambi fissati a `/wealth-compass/`; qualsiasi altro host (Vercel, Netlify, ecc.) deve servire l'app dallo stesso sotto-percorso, oppure devi aggiornare entrambi i valori per adattarli alla radice del tuo host.
