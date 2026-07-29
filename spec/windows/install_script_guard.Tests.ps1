#
# Pester tests for the $LASTEXITCODE exit-code guard pattern used inside the
# powershell_script resource rendered by execute_install_script
# (providers/default.rb, ~line 596).
#
# WHY THESE TESTS EXIST
# =====================
# PowerShell's try/catch only catches *terminating* errors. External programs like
# msiexec.exe signal failure via a non-zero $LASTEXITCODE, not by throwing. Without
# the explicit $LASTEXITCODE check added in this PR, a failed install silently falls
# through, leaving the node with no /opt/chef directory and no backup — an
# indeterminate state that causes random subsequent Chef failures on Windows.
#
# Additionally, a prior msiexec /x (uninstall step) can leave a non-zero
# $LASTEXITCODE that would cause a false positive failure on the install step unless
# $LASTEXITCODE is explicitly reset to $null immediately before the install script runs.
#
# These tests verify both behaviours in pure PowerShell, without needing Chef or a VM.
#
# HOW TO RUN (requires Pester v5, built into Windows 10+)
# ========================================================
#   Invoke-Pester .\spec\windows\install_script_guard.Tests.ps1 -Output Detailed
#
#   If Pester is outdated, update it first:
#   Install-Module -Name Pester -Force -SkipPublisherCheck
#
# WHAT IS TESTED vs. NOT TESTED
# ==============================
# Tested:   the try/catch/$LASTEXITCODE guard logic (pure PowerShell semantics)
# Tested:   filesystem rollback (Move-Item backup -> install dir on failure)
# Tested:   stale $LASTEXITCODE from a prior command causes no false-positive failure
# NOT tested: the full Chef converge, WinRM transport, scheduled task creation,
#             or anything requiring a real Windows VM (use kitchen.yml for those).

BeforeAll {
    # Helper that mirrors the try/catch/$LASTEXITCODE guard block from providers/default.rb.
    # This is a test double of the PowerShell logic Chef interpolates into the upgrade
    # script heredoc — it is NOT imported production code.
    #
    # NOTE: do NOT use this helper for the 'stale $LASTEXITCODE' test — see that context
    # for why it must run the pattern in the caller's scope via dot-sourcing.
    function Invoke-WithExitCodeGuard {
        param(
            [ScriptBlock] $InstallScript,
            [string]      $BackupDir,
            [string]      $InstallDir
        )
        try {
            # Dot-source the install scriptblock so it runs in the current (function)
            # scope. Using & creates a child scope where $LASTEXITCODE is updated but
            # that child scope is discarded on return, leaving this scope's $LASTEXITCODE
            # unchanged.
            # NOTE: we do NOT set $LASTEXITCODE = $null here. Inside a function, that
            # assignment creates a local variable that shadows the automatic $LASTEXITCODE.
            # External processes then update the automatic variable at a higher scope while
            # the check below still reads the local $null shadow — causing a false negative.
            # The $LASTEXITCODE = $null reset that exists in providers/default.rb works
            # because it runs at top-level script scope with no shadowing. That behaviour
            # is tested separately in the 'stale $LASTEXITCODE' context below.
            . $InstallScript
            # PowerShell try/catch only catches *terminating* errors. External programs
            # signal failure via a non-zero exit code, not by throwing, so a failed install
            # would otherwise silently fall through. Explicitly convert a non-zero exit code
            # into a terminating error so the catch block fires and rollback runs.
            if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
                throw "Install script exited with non-zero exit code: $LASTEXITCODE"
            }
        }
        catch {
            if (Test-Path $BackupDir) {
                Move-Item -Path $BackupDir -Destination $InstallDir
            }
            throw
        }
    }
}

Describe 'execute_install_script $LASTEXITCODE guard (providers/default.rb)' {

    BeforeAll {
        $script:testRoot = Join-Path $env:TEMP "chef_pester_$(Get-Random)"
        New-Item -Path $script:testRoot -ItemType Directory | Out-Null
    }

    AfterAll {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:backupDir  = Join-Path $script:testRoot "chef.bak"
        $script:installDir = Join-Path $script:testRoot "chef"
        New-Item -Path $script:backupDir -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $script:backupDir 'sentinel.txt') -Value 'original'
    }

    AfterEach {
        Remove-Item -Path $script:backupDir  -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:installDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'when the install script succeeds (exits 0)' {
        It 'completes without error' {
            { Invoke-WithExitCodeGuard `
                -InstallScript { cmd.exe /c "exit 0" } `
                -BackupDir  $script:backupDir `
                -InstallDir $script:installDir
            } | Should -Not -Throw
        }

        It 'leaves the backup directory untouched — no rollback' {
            Invoke-WithExitCodeGuard `
                -InstallScript { cmd.exe /c "exit 0" } `
                -BackupDir  $script:backupDir `
                -InstallDir $script:installDir

            Test-Path $script:backupDir  | Should -BeTrue
            Test-Path $script:installDir | Should -BeFalse
        }
    }

    Context 'when the install script fails via a non-zero exit code' {
        It 'throws an error containing the failing exit code' {
            { Invoke-WithExitCodeGuard `
                -InstallScript { cmd.exe /c "exit 2" } `
                -BackupDir  $script:backupDir `
                -InstallDir $script:installDir
            } | Should -Throw -ExpectedMessage '*non-zero exit code: 2*'
        }

        It 'reports the exact exit code, not a hardcoded value' {
            { Invoke-WithExitCodeGuard `
                -InstallScript { cmd.exe /c "exit 99" } `
                -BackupDir  $script:backupDir `
                -InstallDir $script:installDir
            } | Should -Throw -ExpectedMessage '*99*'
        }

        It 'moves the backup directory back to the install path (rollback)' {
            { Invoke-WithExitCodeGuard `
                -InstallScript { cmd.exe /c "exit 2" } `
                -BackupDir  $script:backupDir `
                -InstallDir $script:installDir
            } | Should -Throw

            Test-Path $script:backupDir  | Should -BeFalse  # backup was moved
            Test-Path $script:installDir | Should -BeTrue   # restored to install path
            Get-Content (Join-Path $script:installDir 'sentinel.txt') | Should -Be 'original'
        }
    }

    Context 'when the install script throws a terminating error (not an exit code)' {
        It 'also triggers rollback' {
            { Invoke-WithExitCodeGuard `
                -InstallScript { throw 'simulated fatal installer error' } `
                -BackupDir  $script:backupDir `
                -InstallDir $script:installDir
            } | Should -Throw

            Test-Path $script:backupDir  | Should -BeFalse
            Test-Path $script:installDir | Should -BeTrue
            Get-Content (Join-Path $script:installDir 'sentinel.txt') | Should -Be 'original'
        }
    }

    Context 'stale $LASTEXITCODE from a prior command (e.g. msiexec /x uninstall step)' {
        # IMPORTANT: This test does NOT use the Invoke-WithExitCodeGuard helper.
        # If it did, the function's own scope would shadow the outer $LASTEXITCODE = 1,
        # making the test pass regardless of whether the "$LASTEXITCODE = $null" reset
        # line exists in the guard. Instead, we dot-source the pattern directly into the
        # current scope (". { ... }"), which is how the code actually runs in the
        # generated upgrade script — as flat, top-level PowerShell statements.
        It 'does not cause a false-positive failure when the install script itself exits 0' {
            # Step 1: simulate contamination left by a prior command (e.g. msiexec /x)
            cmd.exe /c "exit 1"
            $LASTEXITCODE | Should -Be 1  # confirm the contamination is present

            # Step 2: run the guard pattern inline in this scope — the "$LASTEXITCODE = $null"
            # reset must clear the stale value, otherwise exit 1 triggers a spurious rollback.
            $rolledBack = $false
            . {
                try {
                    $LASTEXITCODE = $null
                    # Use a pure PowerShell cmdlet (no external process) so that
                    # $LASTEXITCODE is not updated by the install script itself.
                    # This is the scenario the reset is guarding against: a prior
                    # step (e.g. msiexec /x) left a stale non-zero $LASTEXITCODE,
                    # and the install logic runs only PowerShell cmdlets.
                    Write-Output 'Install script completed'  # no external process
                    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
                        throw "Install script exited with non-zero exit code: $LASTEXITCODE"
                    }
                }
                catch {
                    $rolledBack = $true
                    if (Test-Path $script:backupDir) {
                        Move-Item -Path $script:backupDir -Destination $script:installDir
                    }
                }
            }

            $rolledBack | Should -BeFalse  # no rollback should have occurred
            Test-Path $script:backupDir  | Should -BeTrue
            Test-Path $script:installDir | Should -BeFalse
        }

        It 'confirms the bug: without the reset, stale exit code 1 causes a false-positive rollback' {
            # This test documents the original buggy behaviour for reference.
            # It deliberately omits "$LASTEXITCODE = $null" to show the failure mode.
            cmd.exe /c "exit 1"   # prior command contaminates $LASTEXITCODE
            $LASTEXITCODE | Should -Be 1

            $rolledBack = $false
            . {
                try {
                    # NO reset here — this is the buggy version.
                    # The install script uses only PowerShell cmdlets (no external
                    # process), so $LASTEXITCODE is NOT overwritten by the install.
                    # This leaves the stale value of 1 from the prior msiexec /x.
                    Write-Output 'Install script completed'  # no external process
                    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
                        throw "Install script exited with non-zero exit code: $LASTEXITCODE"
                    }
                }
                catch {
                    $rolledBack = $true
                    if (Test-Path $script:backupDir) {
                        Move-Item -Path $script:backupDir -Destination $script:installDir
                    }
                }
            }

            # The bug: rollback fires even though the install succeeded
            $rolledBack | Should -BeTrue
        }
    }
}
