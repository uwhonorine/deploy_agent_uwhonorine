# Attendance Tracker – Deploy Agent

`deploy_agent.sh` is a single menu-driven shell script that **deploys**, **runs** and **archives the logs** of the attendance tracker application. It also handles **Ctrl+C / Ctrl+Z** safely while a deployment is in progress.

Repository name: `deploy_agent_uwhonorine`

Youtube Link:``

## Repository contents

```
deploy_agent_uwhonorine/
├── deploy_agent.sh      # the master script (deploy, run, archive + signal handling)
├── templates/           # the three unmodified source files
│   ├── attendance_checker.py
│   ├── config.json
│   └── assets.csv
└── README.md
```

## Requirements

- A Linux shell or WSL with **bash 4+** (the script uses `${var,,}` and GNU `sed -i`)
- `python3`
- `zip`

The script checks for `python3` and `zip` itself and stops with a clear message if either is missing.

## How to run the script

Run it from the **root of the repo**, the folder that contains `templates/`:

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

The main menu appears:

```
===== Deploy Agent =====
1) Deploy the application
2) Run the application
3) Archive the logs
4) Exit
Choose an option:
```

Type the number of the feature you want and press Enter. Any other input shows `Invalid option, try again.` and the menu comes back. The menu loops until you choose `4`.

## The three features

### 1) Deploy

Deployment runs these steps in order:

1. **Pre-flight checks** – `python3` and `zip` are installed, and `templates/` exists.
2. **Name the project** – the folder is created as `attendance_tracker_<name>`. An empty name is rejected. If the folder already exists, you are asked whether to overwrite it (`y` deletes and rebuilds it; anything else aborts without changing anything).
3. **Copy the files** – `attendance_checker.py` goes into the project folder, `config.json` goes into `Helpers/`. Then you choose how to build the roster:
   - **A** – copy the first *N* students from `templates/assets.csv` (the header line is always kept). `total_sessions` stays at `5`.
   - **B** – generate a fresh roster of *N* students (all counts start at `0`) and set `total_sessions` to `1`.
4. **Permissions** – `attendance_checker.py` becomes executable and `config.json` is set to `600` (owner read/write only). The result is printed with `ls -l`.
5. **Thresholds** – optionally change the alert thresholds (see below).
6. **Verify** – the app is run once from inside the new project folder to prove the deployment works.

Inputs are validated: the roster choice must be `A` or `B`, and the student count must be a whole number greater than 0.

### 2) Run

Asks for the project name, checks that `attendance_tracker_<name>` exists, then runs `attendance_checker.py` from inside that folder. If the folder does not exist it tells you to deploy first.

### 3) Archive the logs

See [How log archiving works](#how-log-archiving-works).

## How the threshold update works

After the files are copied, the script asks `Do you want to change the alert thresholds? (y/n)`.

- Anything other than `y` leaves `config.json` exactly as copied from the template.
- On `y`, it asks for two values in turn: the **warning** threshold, then the **failure** threshold.
- Each value must be a whole number from **0 to 100**. Invalid input (letters, negative numbers, values over 100) is rejected and the question repeats.
- Each valid value is written into `Helpers/config.json` with `sed`, which replaces only the number after `"warning":` or `"failure":` and leaves the rest of the file untouched.
- The script then prints the updated lines so you can confirm the change.

Example, entering `80` and `60`:

```
Updated config.json:
    "warning": 80,
    "failure": 60
```

## How log archiving works

When the application runs, it writes two logs into the project's `reports/` folder: `attendance.log` and `absent.log`. Option **3** moves them out of the way so the next run starts clean.

1. Ask for the project name and check the project folder exists.
2. Take one timestamp for the whole operation, in the format `YYYYMMDD_HHMMSS`.
3. For each log (`attendance`, `absent`):
   - If `reports/<log>.log` exists, create `archives/<log>/` (if needed) and **move** the log there as `<log>_<timestamp>.log`.
   - If it does not exist, print `<log>.log does not exist, nothing to archive.` and continue.

Resulting directories and filenames:

```
attendance_tracker_<name>/
├── reports/                      # logs are moved out of here
└── archives/
    ├── attendance/
    │   └── attendance_20261013_125144.log
    └── absent/
        └── absent_20261013_125144.log
```

Because the logs are moved (not copied) and every archive carries its own timestamp, running the archive again later never overwrites an earlier archive.

## How to test the Ctrl+C / Ctrl+Z path

While a deployment is running, the script traps `SIGINT` (Ctrl+C) and `SIGTSTP` (Ctrl+Z). When either arrives, it:

1. prints `Deployment was interrupted!`
2. zips the half-built project folder to `attendance_tracker_<name>_archive.zip` (next to `deploy_agent.sh`)
3. deletes the incomplete project folder, but **only if the zip succeeded** (if zip fails, the folder is left alone)
4. prints `Closing the session.` and exits with status `1`

Ctrl+Z is trapped as well, so the script does not suspend in the background; it cleans up and exits exactly like Ctrl+C.

**To test it:**

```bash
./deploy_agent.sh
# choose 1, enter a name such as "demo", choose A
# at "How many students?" press Ctrl+C   (repeat the test with Ctrl+Z)
```

Then check the result:

```bash
ls                                              # the zip exists, the project folder is gone
unzip -l attendance_tracker_demo_archive.zip    # list what was saved
```

**What the `.zip` contains:** the project folder exactly as it was at the moment of the interruption. Interrupted at the roster prompt, it holds `Helpers/config.json`, `attendance_checker.py` and the empty `reports/` folder. Interrupted at the threshold prompt, it also holds `Helpers/assets.csv`.

Notes on when the trap is active:

- It turns on once the project name has been entered and turns off when deployment finishes (before the verification run). Pressing Ctrl+C at the name prompt, before anything exists, simply ends the script.
- If the interruption arrives before the script has created anything (for example at the "already exists, overwrite?" prompt), the message `Nothing was created yet.` is shown instead of zipping, and the existing folder is left untouched.
- Pressing Ctrl+C on the main menu, or while the app is running afterwards, is not part of the deployment, so it is not intercepted.

## How I tested the deployed application structure

After a deployment I checked the following:

```bash
find attendance_tracker_demo | sort
ls -l attendance_tracker_demo/attendance_checker.py attendance_tracker_demo/Helpers/config.json
cat attendance_tracker_demo/Helpers/config.json
head attendance_tracker_demo/Helpers/assets.csv
```

Expected structure after deploy + run:

```
attendance_tracker_demo/
├── attendance_checker.py      -rwxr-xr-x  (executable)
├── Helpers/
│   ├── assets.csv             (roster from option A or B)
│   └── config.json            -rw-------  (600)
└── reports/                   (logs appear here when the app runs)
```

What I tested:

| Test | Expected result |
|------|-----------------|
| Deploy with roster **A** | `assets.csv` has the header + N rows, `total_sessions` still `5` |
| Deploy with roster **B** | N generated students with `0,0` counts, `total_sessions` is `1` |
| Invalid roster choice / count (`X`, `abc`, `0`) | Rejected, prompt repeats |
| Change thresholds (`80`, `60`) | Only those two numbers change in `config.json` |
| Invalid threshold (`abc`, `150`) | Rejected, prompt repeats |
| Existing project name, answer `n` / `y` | Aborts untouched / rebuilds from scratch |
| Permissions | App is `755`, `config.json` is `600` |
| Run on a missing project | Error message, no crash |
| Archive after a run | Two timestamped files under `archives/attendance/` and `archives/absent/` |
| Archive with no logs | "nothing to archive" for each log |
| Ctrl+C and Ctrl+Z at several prompts | Zip created, folder deleted, exit status `1` |

## Video walkthrough

Link: `<paste video URL here>`

The video covers my approach, how the script is built (one function per deployment step plus the run and archive features), the logic behind each section, a short live marking session, and a demo of interrupting the script mid-deploy.

## How the script is organised

| Section | Purpose |
|---------|---------|
| Shared settings | `TEMPLATES`, `PREFIX`, `IN_PROGRESS` (the folder the trap cleans up) |
| Helpers | `is_number`, `folder_for`, `disarm_trap`, `fail_build`, `on_interrupt` |
| Deploy | `preflight_checks`, `create_structure`, `copy_sources`, `build_roster`, `apply_permissions`, `configure_thresholds`, tied together by `deploy` |
| Run | `run_app` |
| Archive | `archive_logs` |
| Menu | `main_menu` |
