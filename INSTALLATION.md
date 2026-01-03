# Installation Guide

Follow these steps to set up Wealth Compass on your local machine.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Node.js**: v18 or higher ([Download](https://nodejs.org/))
- **Git**: ([Download](https://git-scm.com/))
- **Supabase Account**: For authentication and database ([Sign up](https://supabase.com/))
- **Finnhub API Key**: Free API key for stock prices ([Get key](https://finnhub.io/))

## Setup Instructions

### 1. Clone the Repository

```bash
git clone <YOUR_REPO_URL>
cd wealth-compass
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Configure Supabase

1. Create a new project in your Supabase dashboard.
2. Go to the **SQL Editor** in Supabase and run the following queries to set up the database schema (if you have a schema file, verify it, otherwise ensure tables `transactions`, `investments`, `crypto`, `liabilities`, `liquidity_accounts`, `snapshots` exist).
3. Enable **Authentication** (Email/Password or Magic Link) in Supabase.

### 4. Environment Variables

Create a `.env` file in the root directory by copying the example (if available) or creating a new one.

```bash
touch .env
```

Add the following variables to your `.env` file:

```env
# Supabase Configuration (Required for Auth & DB)
VITE_SUPABASE_URL=your_supabase_project_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key

# Financial Data APIs
VITE_FINNHUB_API_KEY=your_finnhub_api_key
```

> **Note**: You can find your Supabase URL and Anon Key in your Project Settings > API.

### 5. Run the Application

Start the development server:

```bash
npm run dev
```

Open your browser and navigate to `http://localhost:8080` (or the port shown in your terminal).

## Building for Production

To create a production build:

```bash
npm run build
```

The output will be in the `dist` directory, ready to be deployed to Vercel, Netlify, or your preferred host.
