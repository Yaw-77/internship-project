# VIMS — GitHub + Supabase + Netlify

Browser-only deployment: no Docker, local PostgreSQL, local Node.js, or VS Code required. Netlify installs dependencies and builds the React app remotely.

## 1. Upload source to GitHub

Create a **private** GitHub repository. Upload the **contents** of this folder to the repository root using GitHub's web upload interface (do not upload the ZIP as a single file). Keep `.env` files and secrets out of GitHub.

## 2. Create Supabase database

Create a Supabase project at https://supabase.com/dashboard. Open **SQL Editor** and paste the entire `supabase/schema.sql`, then run it **once** on a new project. This creates tables, RLS policies, and an automatic profile trigger. Do not run this script repeatedly on an existing database: policies are not idempotent.

In **Authentication → Providers**, disable public email signups if accounts should be provisioned by the university. In **Authentication → Users**, use **Add user** to create your first administrator with a strong password. The database trigger creates a STUDENT profile automatically.

In **SQL Editor**, promote **only your specific first admin account** (replace email):

```sql
update public.profiles set role = 'ADMIN' where email = 'YOUR_ADMIN_EMAIL@example.com';
```

Never include that promotion SQL in frontend code. Additional accounts can be created in Supabase Auth → Users; then the admin can assign their roles in the VIMS Users screen.

## 3. Get frontend connection settings

Supabase **Project Settings → API / Connect**: copy the project URL and **publishable** key (or legacy anon key). **NEVER** put a service_role or secret key in Netlify `VITE_*` variables.

## 4. Deploy to Netlify

1. Sign in to https://app.netlify.com/ and choose **Add new project → Import an existing project**.
2. Connect your GitHub repository.
3. Base directory: leave empty; build command: `npm run build`; publish directory: `dist` (also in `netlify.toml`).
4. Add environment variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
5. Deploy. Netlify will run npm install/build remotely. After changing env vars, trigger a fresh deploy.
6. Visit the deployed URL and sign in with the administrator account.

## 5. Test in order

- Admin: create a company; assign roles to provisioned accounts; create placement.
- Student: sign in and submit a weekly logbook and attendance.
- University/industry supervisor: review assigned logbook; submit an assessment.
- Industry supervisor: verify assigned attendance.
- Check that users **cannot** read or modify unrelated student placements through the Supabase API.

## Important limitations

This is a functional starter application, **not a certified production student-information system**. It has no file uploads, automated emails, PDF exports, password recovery UI, or bulk onboarding. User provisioning is performed in Supabase Dashboard. Before university-wide rollout: perform end-to-end tests, an RLS/security audit, configure backups, privacy/data-retention policies, monitoring, and university-specific approval. RLS is the security boundary, not the hidden UI controls. Do not use actual student records until access-control testing is complete.

The browser uses Supabase directly, with no Express/Render service. Hosting and database usage may incur costs based on your plans.
