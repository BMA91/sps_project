# Cron setup guide

This project includes a sample cron line in `cron/pipeline.cron`.

## Install the cron job

```bash
crontab cron/pipeline.cron
```

If cron is not running yet:

```bash
sudo service cron start
```

On some systems with systemd, the equivalent may be needed:

```bash
sudo systemctl enable cron
sudo systemctl start cron
```

## Test the cron job

- First, run the project manually with `./run.sh -h` and then with `./run.sh -t`.
- Then copy the sample line into a temporary crontab and inspect the generated log file.
- A quick manual test is:

```bash
/bin/bash /path/to/project/run.sh -t
```

This confirms the job can launch from cron without interactive input.
