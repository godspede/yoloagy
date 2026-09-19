# SPDX-License-Identifier: Apache-2.0
# PowerShell tab completion for yoloagy on Windows. Dot-source it from your
# PowerShell profile:
#   . C:\path\to\yoloagy\completion\yoloagy.ps1
#
# `yoloagy <Tab>` offers the aliases of live sessions named under the current
# directory's prefix, and `yoloagy -<Tab>` completes flags, exactly as in bash:
# this runs completion/yoloagy.bash under Git Bash, so there is one completer.
# Like yoloagy.cmd, it needs `yoloagy` and `yoloagy.cmd` in one directory on
# your PATH.

$script:YoloagyCompletionFile = Join-Path $PSScriptRoot 'yoloagy.bash'

# Git Bash, resolved the way yoloagy.cmd does it, so the System32 WSL bash.exe
# can't shadow it.
$script:YoloagyCompletionBash = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    $(if ($env:ProgramW6432) { Join-Path $env:ProgramW6432 'Git\bin\bash.exe' })
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $script:YoloagyCompletionBash) { $script:YoloagyCompletionBash = 'bash' }

# $1 the bash completer, $2 the current directory (a Windows path), $3 the word.
$script:YoloagyCompletionProgram = @'
cd -- "$(cygpath -u -- "$2")" 2>/dev/null || exit 0
. "$(cygpath -u -- "$1")" || exit 0
COMP_WORDS=(yoloagy "$3"); COMP_CWORD=1; COMPREPLY=()
_yoloagy_complete
[ "${#COMPREPLY[@]}" -gt 0 ] && printf '%s\n' "${COMPREPLY[@]}"
exit 0
'@

$yoloagyCompleter = {
    param($wordToComplete, $commandAst, $cursorPosition)

    $dir = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath } else { $HOME }
    & $script:YoloagyCompletionBash -c $script:YoloagyCompletionProgram yoloagy $script:YoloagyCompletionFile $dir "$wordToComplete" 2>$null |
        Where-Object { $_ } |
        ForEach-Object {
            $type = if ($_ -like '-*') { 'ParameterName' } else { 'ParameterValue' }
            [System.Management.Automation.CompletionResult]::new($_, $_, $type, $_)
        }
}.GetNewClosure()

Register-ArgumentCompleter -Native -CommandName yoloagy, yoloagy.cmd -ScriptBlock $yoloagyCompleter
