Commit any uncommitted work and push to the remote.

Steps:
1. Run `git status` to see what's staged, unstaged, and untracked.
2. Run `git diff` to review any unstaged changes.
3. If there are uncommitted changes to repo artifacts (tools, skills, commands, staging files, CLAUDE.md, README.md):
   a. Check that README.md and CLAUDE.md tables are up to date for anything new or modified. Fix any missing entries before committing.
   b. Stage the relevant files explicitly (never `git add .` — don't accidentally include backups/ or logs/).
   c. Commit with a clear message and the Co-Authored-By trailer.
4. If there is nothing to commit (working tree clean or only ignored files), say so and skip to step 5.
5. Run `git push` to push the current branch to origin.
6. Confirm the push succeeded and report the remote URL and branch.

Do not push if the push would require force-push. Warn Marty instead.
