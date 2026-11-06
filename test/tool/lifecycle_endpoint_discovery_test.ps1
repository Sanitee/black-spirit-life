Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:passed=0
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:passed++}
$harness=Join-Path $PSScriptRoot '../../tool/release/run_lifecycle_rehearsal.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
Assert-True ($errors.Count -eq 0) 'Harness parses.'
foreach($name in @('Get-TestFishListener','Get-TestFishToken','Invoke-TestFishHealth')){
 $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name}.GetNewClosure(),$true)
 Assert-True ($null -ne $function) ('Missing function '+$name)
 Invoke-Expression $function.Extent.Text
}
$script:records=@();$script:respond=$true;$script:requests=@()
function Get-TestProcessRecords([string]$InstallRoot){$script:records}
function Invoke-WebRequest {param($Uri,$Headers,[switch]$UseBasicParsing,$TimeoutSec)
 $script:requests+=@{uri=$Uri;token=$Headers['X-BSL-API-Token']}
 if(-not $script:respond){throw 'Synthetic failed or unauthorized endpoint.'}
 [pscustomobject]@{StatusCode=200}
}
foreach($command in @('service --port 8765 --api-token synthetic_token','"service" "--port" "8765" "--api-token" "synthetic_token"')){
 $script:records=@([pscustomobject]@{Name='fish_companion_service.exe';ProcessId=42;CommandLine=$command})
 $found=Get-TestFishListener 'synthetic-install'
 Assert-True ($null -ne $found -and $found.ServiceProcessId -eq 42 -and $found.Port -eq 8765) 'Quoted/unquoted exact service found.'
 Assert-True ($script:requests[-1].uri -ceq 'http://127.0.0.1:8765/api/health' -and $script:requests[-1].token -ceq 'synthetic_token') 'Actual discovery requires authenticated loopback request.'
}
$script:respond=$false
Assert-True ($null -eq (Get-TestFishListener 'synthetic-install')) 'Failed authentication or startup must not count as ready.'
$script:respond=$true
foreach($command in @('service --port 443 --api-token synthetic_token','service --port 8796 --api-token synthetic_token','service --port 8765','service --port 8765 --api-token "invalid token"','service --port 8765 --api-tokenX synthetic_token')){
 $script:records=@([pscustomobject]@{Name='fish_companion_service.exe';ProcessId=42;CommandLine=$command})
 Assert-True ($null -eq (Get-TestFishListener 'synthetic-install')) 'Invalid port/token/flag rejected.'
}
$script:records=@()
Assert-True ($null -eq (Get-TestFishListener 'synthetic-install')) 'A response without a scoped running process cannot pass.'
Write-Output "PASS: $script:passed lifecycle endpoint assertions."
