# yoloagy

`yoloagy` starts agy, the Google Antigravity CLI, inside a tmux session, or
reattaches to the one already running. If your SSH connection drops, agy keeps
running; SSH back in, run the same command, and you are back in the
conversation.

It is one bash script. It also:

- names sessions after the directory you start them in, so `yoloagy 2` in two
  different projects gives two different sessions;
- runs each session on its own tmux server, so sessions never share a client or
  a "current session";
- gives each named session started from a git repository's main checkout its
  own git worktree, so parallel agents do not edit the same files or share a
  branch;
- sets tmux's `escape-time` to 10ms so Esc reaches agy immediately;
- runs on Windows under Git Bash with psmux.

## Install

Requirements: bash, tmux (psmux on Windows), git for worktree isolation, and
`agy` on your `PATH` or in `~/.local/bin`, where its installer puts it.

Put the script on your `PATH`, by copying or by symlinking from a clone:

```bash
git clone https://github.com/godspede/yoloagy.git ~/src/yoloagy
ln -s ~/src/yoloagy/yoloagy ~/.local/bin/yoloagy
```

For tab completion of flags and live session names, add this to `~/.bashrc`:

```bash
source ~/src/yoloagy/completion/yoloagy.bash
```

## Usage

```
yoloagy                       session "agy", in the current directory
yoloagy <alias>               session "<prefix>-<alias>"
yoloagy --restart [<alias>]   kill the session (if any) and start a fresh one
yoloagy --detach  [<alias>]   create the session but do not attach
yoloagy --here    [<alias>]   launch in the current directory, no worktree
yoloagy --no-worktree [<alias>]   same as --here
yoloagy -l, --list            list live yoloagy sessions
yoloagy --prefix              print the session-name prefix for this directory
yoloagy -h, --help            show help
```

Running `yoloagy <alias>` a second time attaches to the running session rather
than starting another. Use `--restart` to replace it.

Detach and leave agy running with the tmux prefix key and then `d` (Ctrl-b and
then d, unless you have rebound the prefix). To end a session, exit agy, or run
`tmux -L <session> kill-server`.

`--detach` prints `session=<name>` and `dir=<path>` lines, so a script can start
a session and learn its name and working directory without a terminal.

Set `YOLOAGY_AGY` to run a different agy binary or wrapper.

### Session names

The prefix is the current directory's name. Directory names that don't
identify a project on their own (`repo`, `src`, `code`, `scripts`, `bin`,
`tools`, and a few others) are skipped, walking up until one does. From
`~/src/webapp/scripts`, `yoloagy 2` opens session `webapp-2`. Your home
directory gives the prefix `home`.

Inside a session's worktree (`<repo>/.worktrees/<session>`) the prefix is the
repository's, so the same alias finds the same session from either place.

Aliases may contain letters, digits, `-` and `_`.

## Worktree isolation

Two agents working in the same checkout share one working tree, one index and
one `HEAD`. One agent's `git add -A` picks up the other's unfinished edits, and
a branch switch in one moves the other.

So when you start a named session (`yoloagy <alias>`) from a repository's main
checkout, yoloagy creates a linked worktree for it:

- path `<repo>/.worktrees/<session>`, on branch `yolo/<session>`;
- based on the remote's default branch after a best-effort fetch, falling back
  to a local `main` or `master`, then to the current branch;
- reused on later launches of the same session.

It launches in place instead when:

- you run bare `yoloagy` with no alias;
- the current directory is already inside a linked worktree;
- the current directory is not in a git repository;
- you pass `--here` or `--no-worktree`;
- you are on Windows.

If creating the worktree fails, yoloagy prints why and launches in the current
directory. Add `.worktrees/` to the repository's `.gitignore`. yoloagy does not
remove worktrees; use `git worktree remove` when you are done with one.

## Windows

`yoloagy.cmd` runs the bash script under Git Bash, which drives psmux. Put both
`yoloagy` and `yoloagy.cmd` in the same directory on your `PATH`, and install
psmux with `winget install marlocarlo.psmux`.

- yoloagy looks for psmux's `tmux.exe` under
  `%LOCALAPPDATA%\Microsoft\WinGet\Packages` first, because Git Bash can refuse
  to run the WinGet `tmux` shim.
- Windows Defender sometimes quarantines psmux's `tmux.exe` as
  `Behavior:Win32/Execution.A!ml`, a false positive. yoloagy reports the
  missing binary and how to restore it.
- yoloagy unsets `SSH_CONNECTION`, `SSH_CLIENT` and `SSH_TTY` before starting
  psmux. When `SSH_CONNECTION` is set, psmux turns Ctrl+J into Enter, so Ctrl+J
  submits the prompt instead of inserting a newline. This needs psmux 3.3.7 or
  later.
- The psmux pane runs agy through your default shell (usually pwsh), which
  loads your PowerShell profile. A `Set-Location` in that profile overrides the
  directory yoloagy starts the session in.
- Worktree isolation is off on Windows.

## Gating agy's commands

yoloagy starts agy without `--dangerously-skip-permissions`. That flag approves
every prompt, including a prompt that a command gate raised because it wanted
you to decide. Without it, agy's own `toolPermission` setting and any hook you
install decide what runs.

[construct-auto-classifier](https://github.com/godspede/construct-auto-classifier)
is such a gate. It is a PreToolUse hook that classifies each shell command
before agy runs it: safe commands run, risky ones are sent back to the agent
with a reason, and a repeated risky command is escalated to you. With yoloagy,
set it up like this:

1. Install the hook at user scope in `~/.gemini/config/hooks.json`, so every
   agy session on the machine is gated. The exact block is in the
   construct-auto-classifier README.
2. Set `"toolPermission": "request-review"` in
   `~/.gemini/antigravity-cli/settings.json`. agy then asks before every
   command.
3. Set `"agy": { "autoAcceptInTmux": true }` in the gate's config. When the gate
   allows a command, it answers agy's prompt for that command in agy's tmux
   pane.

Inside a yoloagy session, allowed commands then run without a prompt, and the
only command prompts you see are the gate's escalations, which show its reason.
If the gate is not installed, crashes, or times out, nothing answers the prompt
and you decide every command yourself.

The gate finds the pane from the `TMUX` and `TMUX_PANE` variables that tmux
sets inside it, so it reaches yoloagy's per-session server without extra
configuration. Under psmux on Windows this depends on psmux setting those
variables and on `tmux` being runnable from the hook; check it on your machine
before relying on it.

## Tests

`tests/smoke.sh` runs on Linux or macOS with tmux and git. It uses a stub `agy`
and a private `TMUX_TMPDIR`, so it never sees or touches your own tmux
sessions:

```bash
bash tests/smoke.sh
```

<sub><i>Forged on construct/famelos</i></sub>

## License

Apache-2.0. See [LICENSE](LICENSE).
