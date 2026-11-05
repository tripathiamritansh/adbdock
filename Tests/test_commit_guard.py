"""Exercise the actual commit guard in a disposable repository; no real secrets."""
import os
from pathlib import Path
import subprocess
import tempfile

hook = Path(__file__).resolve().parents[1] / "hooks/pre-commit"
public_email = "17977913+tripathiamritansh@users.noreply.github.com"
with tempfile.TemporaryDirectory(prefix="adbdock-hook-") as directory:
    root = Path(directory)
    env = os.environ.copy()
    for key in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"):
        env.pop(key, None)

    def git(*args):
        return subprocess.run(["git", *args], cwd=root, env=env, check=True, capture_output=True)

    def guard(**overrides):
        return subprocess.run(["bash", str(hook)], cwd=root, env={**env, **overrides},
                              capture_output=True, text=True)

    git("init", "-q")
    git("config", "user.email", public_email)
    (root / "sample.txt").write_text("ordinary content\n")
    git("add", "sample.txt")
    assert guard().returncode == 0

    # Construct only a synthetic pattern, not a usable credential.
    sample = "gh" + "p_" + "synthetic-fixture"
    (root / "sample.txt").write_text(sample + "\n")
    git("add", "sample.txt")
    result = guard()
    assert result.returncode != 0 and sample not in result.stdout + result.stderr

    private_email = "private@example.invalid"
    git("config", "user.email", private_email)
    result = guard()
    assert result.returncode != 0 and private_email not in result.stdout + result.stderr
    git("config", "user.email", public_email)
    result = guard(GIT_AUTHOR_EMAIL=private_email)
    assert result.returncode != 0 and private_email not in result.stdout + result.stderr
    print("Passed 4 commit-guard checks")
