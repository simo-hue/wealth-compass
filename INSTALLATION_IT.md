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
cd wealth-compass
```

### 2. Installa le Dipendenze

```bash
npm install
```

### 3. Configura Supabase

1. Crea un nuovo progetto nella dashboard di Supabase.
2. Vai all'**Editor SQL** in Supabase ed esegui le query necessarie per impostare lo schema del database (assicurati che esistano le tabelle `transactions`, `investments`, `crypto`, `liabilities`, `liquidity_accounts`, `snapshots`).
3. Abilita l'**Autenticazione** (Email/Password o Magic Link) nelle impostazioni di Supabase.

### 4. Variabili d'Ambiente

Crea un file `.env` nella directory principale copiando l'esempio (se disponibile) o creandone uno nuovo.

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

I file generati si troveranno nella cartella `dist`, pronti per essere caricati su Vercel, Netlify o il tuo hosting preferito.
