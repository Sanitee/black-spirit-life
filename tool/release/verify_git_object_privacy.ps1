[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PolicyPath
)

# Data-only policy bridge. Never dot-source or invoke the candidate verifier.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-StaticPolicyValue {
    param([System.Management.Automation.Language.Ast]$Node)
    if ($Node -is [System.Management.Automation.Language.CommandExpressionAst]) {
        if ($Node.Redirections.Count -ne 0) { throw 'policy-expression' }
        return Read-StaticPolicyValue $Node.Expression
    }
    if ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Node.Value
    }
    if ($Node -is [System.Management.Automation.Language.ParenExpressionAst]) {
        return Read-StaticPolicyValue $Node.Pipeline
    }
    if ($Node -is [System.Management.Automation.Language.PipelineAst]) {
        if ($Node.PipelineElements.Count -ne 1) { throw 'policy-expression' }
        return Read-StaticPolicyValue $Node.PipelineElements[0]
    }
    if ($Node -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        return ,@(Read-StaticPolicyValue $Node.SubExpression)
    }
    if ($Node -is [System.Management.Automation.Language.StatementBlockAst]) {
        if ($null -ne $Node.Traps -and $Node.Traps.Count -gt 0) { throw 'policy-expression' }
        foreach ($statement in $Node.Statements) { Read-StaticPolicyValue $statement }
        return
    }
    if ($Node -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        foreach ($element in $Node.Elements) { Read-StaticPolicyValue $element }
        return
    }
    if ($Node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
        $Node.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
        $left = Read-StaticPolicyValue $Node.Left
        $right = Read-StaticPolicyValue $Node.Right
        if ($left -isnot [string] -or $right -isnot [string]) { throw 'policy-expression' }
        return $left + $right
    }
    throw 'policy-expression'
}

try {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $PolicyPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) { throw 'policy-parse' }
    $names = @('excludedRelativePaths', 'generatedPathPattern',
        'browserStatePathPattern', 'sessionImportReceiptPathPattern',
        'customIconPathPattern', 'personalDataFilePattern',
        'databaseOrSidecarPattern', 'temporaryArtifactPattern', 'secretPattern',
        'machinePathPattern', 'machinePathFixtureAllowlist', 'textExtensions')
    $policy = [ordered]@{}
    foreach ($name in $names) {
        $assignments = @($ast.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -ceq $name
        }, $true))
        if ($assignments.Count -ne 1) { throw 'policy-assignment' }
        $policy[$name] = Read-StaticPolicyValue $assignments[0].Right
    }
    # Extract the two inline tracked-generated patterns, not a handwritten copy.
    $tracked = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -ceq '$trackedGeneratedOutputs'
    }, $true))
    if ($tracked.Count -ne 1) { throw 'policy-tracked-generated' }
    $matches = @($tracked[0].Right.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
        $node.Operator -eq [System.Management.Automation.Language.TokenKind]::Imatch
    }, $true))
    if ($matches.Count -ne 2) { throw 'policy-tracked-generated' }
    $policy['trackedGeneratedPatterns'] = @($matches | ForEach-Object {
        Read-StaticPolicyValue $_.Right
    })
    $markers = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -ceq '$privateMachineMarkers'
    }, $true))
    if ($markers.Count -ne 1 -or
        ($markers[0].Right.Extent.Text -replace '\s', '') -cne '@($env:USERPROFILE)') {
        throw 'policy-marker-source'
    }
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $policy['_bridgeRuntime'] = $PSVersionTable.PSVersion.ToString()
    $policy | ConvertTo-Json -Depth 8 -Compress
}
catch {
    # Parser diagnostics can contain private source lines and absolute paths.
    [Console]::Error.WriteLine('Git privacy policy extraction failed.')
    exit 1
}
