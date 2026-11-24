# Connecting the app to Supabase

**What Supabase is:** an online database plus sign-in service. Right now the
app runs in *demo mode*, with fake data stored only on your phone. Supabase
makes the data real: it's saved online, shared between friends, and survives
reinstalling the app.

The setup has two parts. **Do Part A first.** Part B (Google sign-in) can
wait.

---

## Part A: Create the database (about 10 minutes)

### A1. Create a project
1. Go to <https://supabase.com> → **Start your project** and sign up
   (signing in with GitHub is easiest).
2. Click **New project**.
   - **Name:** anything, for example `split-app`
   - **Database password:** click **Generate**, then save it in your password
     manager. *Don't send it to anyone, including me.*
   - **Region:** the one closest to you (for India: *Mumbai*)
3. Click **Create new project** and wait about 2 minutes while it sets up.

### A2. Create the tables (copy and paste once)
1. In the left sidebar, click **SQL Editor** (the `>_` icon).
2. Click **+ New query**.
3. Open `supabase/setup.sql` from this project, select all (⌘A), copy (⌘C)
   and paste it into the editor.
4. Click **Run** (or press ⌘↵). You should see **"Success. No rows
   returned"**.
   - If you see a warning about "destructive operations", click
     **Run this query** to continue. It's expected.
   - If you see an error, send me a screenshot. Don't try to fix it by hand.

### A3. Copy two values and send them to me
1. Click **Project Settings** (the gear at the bottom left) → **API Keys**.
2. Copy the **Publishable key** (it starts with `sb_publishable_`).
3. Go to **Project Settings** → **Data API** and copy the **Project URL**
   (`https://something.supabase.co`).

Send me those **two** values. They are designed to be public: they're
built into every app.
**Never send** the `secret` / `service_role` key or the database password.

Once I have them, I'll check the database is set up correctly from here.

---

## Part B: Google sign-in (about 15 minutes, can wait)

The app needs Google sign-in to tell people apart. This part happens in
Google Cloud, not in Supabase.

### B1. Google Cloud project
1. Go to <https://console.cloud.google.com> and sign in with your Google
   account.
2. At the top, click the project picker → **New project** → name it
   `split-app` → **Create**.
3. Search for **"Google Auth Platform"** → **Get started**.
   - App name: your app's name. Support email: yours.
   - Audience: **External**. Contact email: yours. Then **Create**.

### B2. Create 3 "OAuth client IDs"
Go to **Google Auth Platform → Clients → + Create client** three times:

| # | Application type | Fill in |
|---|---|---|
| 1 | **Web application** | Name: `Supabase`. Leave everything else empty. **Copy the Client ID and Client secret.** |
| 2 | **Android** | Package name: `com.satabata.app`. SHA-1: `51:C4:8B:D0:5A:78:45:89:3C:15:2A:3E:8C:1B:90:31:FB:0A:C5:4F` |
| 3 | **iOS** | Bundle ID: `com.satabata.app`. **Copy the Client ID.** |

(The package name and SHA-1 belong to this project and computer. I already
looked them up.)

### B3. Turn on Google in Supabase
Supabase → **Authentication** → **Sign In / Providers** → **Google**:
- **Enable**: on
- **Client IDs**: the Web client ID, then a comma, then the iOS client ID
- **Client Secret**: the Web client secret (this is the *only* place it goes)
- **Skip nonce checks**: on
- **Save**

### B4. Send me
- the **Web client ID**
- the **iOS client ID**

Both end in `.apps.googleusercontent.com` and are safe to share. Don't send
the client secret.

---

## What I do with your values

I put them in `config/dev.json` (this file is never uploaded to git) and
run:

```bash
flutter run --dart-define-from-file=config/dev.json
```

## Database updates

When the app gets a new feature that needs the database, there's a new file in
`supabase/migrations/`. Run each one once, in order, in **SQL Editor → New
query → paste → Run**. (`setup.sql` already includes all of them, for a fresh
project.)

| File | Adds | Needed for |
|---|---|---|
| `0005_invites_delete_groups.sql` | invite codes, deleting groups | "Join a group", "Delete group" |

## Optional: extras

- **Recurring expenses on a schedule:** go to Supabase → Database →
  Extensions, enable **pg_cron**, then run
  `supabase/migrations/0003_schedule_recurring.sql` in the SQL editor.
  Without it, repeats are still created, but only when someone opens the
  app.
- **Changing the app name or ID later:** see `docs/RENAMING.md`. If you
  change the ID, update the Android and iOS clients from step B2 to match.
