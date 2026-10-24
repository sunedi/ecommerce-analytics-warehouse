<#
.SYNOPSIS
Builds the EcommerceDW database and loads the Olist files, then runs the checks.

.DESCRIPTION
Runs every SQL script in order with sqlcmd and stops at the first error.
Run scripts/get_data.py first so the CSV files are in data/raw.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\build.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Server 'localhost\SQLEXPRESS'
#>
param(
    [string]$Server = '(localdb)\MSSQLLocalDB'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# sqlcmd reads environment variables as scripting variables, so $(DataDir) in the SQL becomes
# this path. (Passing it with -v fails when the path contains spaces.)
$env:DataDir = Join-Path $root 'data'

$scripts = @(
    'sql\00_setup\01_create_database.sql',
    'sql\00_setup\02_create_schemas.sql',
    'sql\00_setup\03_create_audit_tables.sql',
    'sql\01_raw\01_create_raw_tables.sql',
    'sql\01_raw\02_create_load_procedure.sql',
    'sql\01_raw\03_run_load.sql',
    'tests\01_raw_load_checks.sql',
    'sql\02_staging\01_create_staging_tables.sql',
    'sql\02_staging\02_create_load_procedure.sql',
    'sql\02_staging\03_create_column_profiler.sql',
    'sql\02_staging\04_run_load.sql',
    'tests\02_staging_checks.sql',
    'sql\03_warehouse\01_create_tables.sql',
    'sql\03_warehouse\02_create_load_procedure.sql',
    'sql\03_warehouse\03_run_load.sql',
    'tests\03_warehouse_checks.sql',
    'sql\04_marts\01_create_tables.sql',
    'sql\04_marts\02_create_load_procedure.sql',
    'sql\04_marts\03_run_load.sql',
    'tests\04_mart_checks.sql',
    'sql\05_controls\01_create_tables.sql',
    'sql\05_controls\02_create_procedure.sql',
    'sql\05_controls\03_run_controls.sql',
    'tests\05_control_checks.sql'
)

foreach ($script in $scripts) {
    Write-Host "==> $script"
    # -E Windows login, -b stop on error, -I QUOTED_IDENTIFIER ON
    sqlcmd -S $Server -E -b -I -i (Join-Path $root $script)
    if ($LASTEXITCODE -ne 0) {
        throw "Build stopped: $script failed."
    }
}

Write-Host 'Build finished.'
