[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(feat|fix|security|style|refactor|perf|docs|test|build|ci|chore)(\([a-zA-Z0-9._/-]+\))?(!)?:\s+\S.+$')]
    [string] $CommitMessage,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ReleaseTitle,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Files,

    [Parameter(Mandatory = $false)]
    [string] $Description = '',

    [Parameter(Mandatory = $false)]
    [string[]] $Changes = @(),

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Patch', 'Minor', 'Major')]
    [string] $Bump = 'Auto',

    [Parameter(Mandatory = $false)]
    [switch] $SkipValidation,

    [Parameter(Mandatory = $false)]
    [switch] $NoConfirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string] $Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string] $Message)
    Write-Host "[AVISO] $Message" -ForegroundColor Yellow
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [Parameter(Mandatory = $false)]
        [switch] $AllowFailure
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $previousErrorActionPreference = $ErrorActionPreference

    $hasNativePreference = Test-Path 'variable:PSNativeCommandUseErrorActionPreference'
    if ($hasNativePreference) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        # No Windows PowerShell 5.1, avisos do Git em stderr viram ErrorRecord.
        # O código de saída, verificado abaixo, determina se o comando falhou.
        $ErrorActionPreference = 'Continue'
        & git @Arguments 1> $stdoutFile 2> $stderrFile
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference

        $stdout = @()
        if ((Test-Path -LiteralPath $stdoutFile) -and ((Get-Item -LiteralPath $stdoutFile).Length -gt 0)) {
            $stdout = @(Get-Content -LiteralPath $stdoutFile)
        }

        $stderr = @()
        if ((Test-Path -LiteralPath $stderrFile) -and ((Get-Item -LiteralPath $stderrFile).Length -gt 0)) {
            $stderr = @(Get-Content -LiteralPath $stderrFile)
        }

        if ($exitCode -ne 0 -and -not $AllowFailure) {
            $commandText = 'git ' + ($Arguments -join ' ')
            $details = (@($stdout) + @($stderr) | Out-String).Trim()
            throw "Falha ao executar: $commandText`n$details"
        }

        return [PSCustomObject]@{
            ExitCode    = $exitCode
            Output      = $stdout
            ErrorOutput = $stderr
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }

        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-GitText {
    param([string[]] $Arguments)
    $result = Invoke-Git -Arguments $Arguments
    return (($result.Output | Out-String).Trim())
}

function Invoke-Npm {
    param([string[]] $Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    $hasNativePreference = Test-Path 'variable:PSNativeCommandUseErrorActionPreference'
    if ($hasNativePreference) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        $ErrorActionPreference = 'Continue'
        & $script:NpmExecutable @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }

    if ($exitCode -ne 0) {
        throw "Falha ao executar npm.cmd $($Arguments -join ' ')."
    }
}

function Normalize-GitPath {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'A lista de arquivos contém um caminho vazio.'
    }

    $normalized = $Path.Trim().Replace('\', '/')
    while ($normalized.StartsWith('./')) {
        $normalized = $normalized.Substring(2)
    }

    if ([System.IO.Path]::IsPathRooted($normalized)) {
        throw "Use caminhos relativos à raiz do projeto: $Path"
    }

    if ($normalized -match '(^|/)\.\.(/|$)') {
        throw "O caminho não pode sair da raiz do projeto: $Path"
    }

    return $normalized
}

function Get-ChangedFiles {
    $all = New-Object System.Collections.Generic.List[string]

    foreach ($line in (Invoke-Git -Arguments @('diff', '--name-only', '--')).Output) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $all.Add((Normalize-GitPath $line))
        }
    }

    foreach ($line in (Invoke-Git -Arguments @('diff', '--cached', '--name-only', '--')).Output) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $all.Add((Normalize-GitPath $line))
        }
    }

    foreach ($line in (Invoke-Git -Arguments @('ls-files', '--others', '--exclude-standard')).Output) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $all.Add((Normalize-GitPath $line))
        }
    }

    return @($all | Sort-Object -Unique)
}

function Get-LatestSemVerTag {
    $tags = (Invoke-Git -Arguments @(
        'tag',
        '--merged', 'HEAD',
        '--list', 'v[0-9]*.[0-9]*.[0-9]*',
        '--sort=-v:refname'
    )).Output

    foreach ($tag in $tags) {
        $candidate = $tag.Trim()
        if ($candidate -match '^v\d+\.\d+\.\d+$') {
            return $candidate
        }
    }

    return 'v0.0.0'
}

function Get-CommitRecords {
    param([string] $BaseTag)

    $range = if ($BaseTag -eq 'v0.0.0') { 'HEAD' } else { "$BaseTag..HEAD" }
    $format = '%H%x1f%s%x1f%b%x1e'
    $rawResult = Invoke-Git -Arguments @('log', $range, "--format=$format", '--reverse')
    $raw = ($rawResult.Output -join "`n")

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($chunk in ($raw -split [char]0x1e)) {
        $clean = $chunk.Trim("`r", "`n", ' ')
        if ([string]::IsNullOrWhiteSpace($clean)) {
            continue
        }

        $parts = @($clean -split [char]0x1f, 3)
        if (@($parts).Count -lt 2) {
            continue
        }

        $records.Add([PSCustomObject]@{
            Hash    = $parts[0].Trim()
            Subject = $parts[1].Trim()
            Body    = if (@($parts).Count -ge 3) { $parts[2].Trim() } else { '' }
        })
    }

    return $records.ToArray()
}

function Get-CommitType {
    param([string] $Subject)

    if ($Subject -match '^(?<type>feat|fix|security|style|refactor|perf|docs|test|build|ci|chore)(\([^)]+\))?(!)?:') {
        return $Matches['type'].ToLowerInvariant()
    }

    return 'other'
}

function Get-AutomaticBump {
    param([object[]] $Commits)

    foreach ($commit in $Commits) {
        $text = "$($commit.Subject)`n$($commit.Body)"
        if ($commit.Subject -match '^[a-zA-Z]+(\([^)]+\))?!:' -or $text -match '(?im)^BREAKING[ -]CHANGE:\s*\S') {
            return 'Major'
        }
    }

    foreach ($commit in $Commits) {
        if ((Get-CommitType $commit.Subject) -eq 'feat') {
            return 'Minor'
        }
    }

    return 'Patch'
}

function Get-NextVersion {
    param(
        [string] $BaseTag,
        [ValidateSet('Patch', 'Minor', 'Major')]
        [string] $SelectedBump
    )

    if ($BaseTag -notmatch '^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
        throw "Tag base inválida: $BaseTag"
    }

    $major = [int] $Matches['major']
    $minor = [int] $Matches['minor']
    $patch = [int] $Matches['patch']

    switch ($SelectedBump) {
        'Major' {
            $major++
            $minor = 0
            $patch = 0
        }
        'Minor' {
            $minor++
            $patch = 0
        }
        'Patch' {
            $patch++
        }
    }

    return "$major.$minor.$patch"
}

function Escape-MarkdownText {
    param([string] $Text)
    return ($Text -replace '\|', '\|').Trim()
}

function Add-CommitSection {
    param(
        [System.Collections.Generic.List[string]] $Lines,
        [string] $Heading,
        [object[]] $Commits
    )

    if (@($Commits).Count -eq 0) {
        return
    }

    $Lines.Add("## $Heading")
    $Lines.Add('')

    foreach ($commit in $Commits) {
        $Lines.Add("- **$(Escape-MarkdownText $commit.Subject)**")

        $bodyLines = @($commit.Body -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^(BREAKING[ -]CHANGE:|Co-authored-by:)'
        })

        foreach ($bodyLine in $bodyLines) {
            $cleanBody = $bodyLine -replace '^[-*]\s+', ''
            if (-not [string]::IsNullOrWhiteSpace($cleanBody)) {
                $Lines.Add("  - $(Escape-MarkdownText $cleanBody)")
            }
        }
    }

    $Lines.Add('')
}

function Write-Utf8NoBom {
    param(
        [string] $Path,
        [string[]] $Lines
    )

    $content = ($Lines -join [Environment]::NewLine) + [Environment]::NewLine
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $content, $encoding)
}

function Invoke-FileValidations {
    param([string[]] $StagedFiles)

    Write-Step 'Executando validações'
    Invoke-Git -Arguments @('diff', '--cached', '--check') | Out-Null
    Write-Ok 'git diff --cached --check concluído'

    $jsFiles = @($StagedFiles | Where-Object { $_ -match '\.js$' -and (Test-Path -LiteralPath $_) })
    foreach ($file in $jsFiles) {
        & $script:NodeExecutable --check $file
        if ($LASTEXITCODE -ne 0) {
            throw "Falha na validação JavaScript de $file."
        }
        Write-Ok "JavaScript válido: $file"
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'A publicação do MPTreco deve ser executada no Windows.'
}

Write-Step 'Validando ambiente de publicação'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git não foi encontrado no PATH.'
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
    throw 'Node.js não foi encontrado no PATH.'
}
$script:NodeExecutable = $nodeCommand.Source

$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npmCommand) {
    throw 'npm.cmd não foi encontrado no PATH.'
}
$script:NpmExecutable = $npmCommand.Source

$rootResult = Invoke-Git -Arguments @('rev-parse', '--show-toplevel')
$root = (($rootResult.Output | Select-Object -First 1).ToString()).Trim()
if ([string]::IsNullOrWhiteSpace($root)) {
    throw 'Não foi possível determinar a raiz do repositório.'
}
Set-Location $root

$branch = Get-GitText @('branch', '--show-current')
if ($branch -ne 'main') {
    throw "A publicação oficial deve ocorrer na branch main. Branch atual: $branch"
}

$remoteCheck = Invoke-Git -Arguments @('remote', 'get-url', 'origin') -AllowFailure
if ($remoteCheck.ExitCode -ne 0) {
    throw 'O remote origin não está configurado.'
}

$requiredFiles = @(
    'package.json',
    'package-lock.json',
    '.github/workflows/publicar-release-oficial.yml'
)
foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Arquivo obrigatório não encontrado: $requiredFile"
    }
}

$requiredBinaries = @(
    'bin/yt-dlp.exe',
    'bin/ffmpeg.exe',
    'bin/ffprobe.exe'
)
foreach ($requiredBinary in $requiredBinaries) {
    if (-not (Test-Path -LiteralPath $requiredBinary)) {
        throw "Ferramenta ausente: $requiredBinary. Execute npm.cmd install ou npm.cmd run preparar antes da publicação."
    }
}

Write-Ok "Repositório: $root"
Write-Ok 'Branch: main'

Write-Step 'Sincronizando referências remotas'
Invoke-Git -Arguments @('fetch', 'origin', '--tags', '--prune') | Out-Null

$remoteMainCheck = Invoke-Git -Arguments @('rev-parse', '--verify', 'origin/main') -AllowFailure
if ($remoteMainCheck.ExitCode -ne 0) {
    throw 'A referência origin/main não foi encontrada.'
}

$head = Get-GitText @('rev-parse', 'HEAD')
$remoteHead = Get-GitText @('rev-parse', 'origin/main')
$mergeBase = Get-GitText @('merge-base', 'HEAD', 'origin/main')

if ($head -ne $remoteHead) {
    if ($mergeBase -eq $head) {
        throw 'A branch local está atrás de origin/main. Execute git pull --ff-only origin main antes de publicar.'
    }

    if ($mergeBase -ne $remoteHead) {
        throw 'A branch local divergiu de origin/main. Resolva a sincronização antes de publicar.'
    }

    Write-Warn 'A branch local já possui commit(s) ainda não enviados; eles serão incluídos na versão.'
}

$normalizedFiles = @($Files | ForEach-Object { Normalize-GitPath $_ } | Sort-Object -Unique)
$currentChanges = @(Get-ChangedFiles)

if (@($currentChanges).Count -eq 0) {
    throw 'Não existem alterações locais para publicar.'
}

$extraChanges = @($currentChanges | Where-Object { $normalizedFiles -notcontains $_ })
if (@($extraChanges).Count -gt 0) {
    $list = ($extraChanges | ForEach-Object { " - $_" }) -join "`n"
    throw "Existem arquivos alterados que não foram informados em -Files:`n$list`nInclua-os conscientemente ou limpe-os antes da publicação."
}

foreach ($file in $normalizedFiles) {
    $trackedCheck = Invoke-Git -Arguments @('ls-files', '--error-unmatch', '--', $file) -AllowFailure
    $headTrackedCheck = Invoke-Git -Arguments @('cat-file', '-e', "HEAD:$file") -AllowFailure
    if (-not (Test-Path -LiteralPath $file) -and $trackedCheck.ExitCode -ne 0 -and $headTrackedCheck.ExitCode -ne 0) {
        throw "Arquivo informado não existe e não é rastreado pelo Git: $file"
    }
}

$commitBodyLines = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($Description)) {
    $commitBodyLines.Add($Description.Trim())
}
if (@($Changes).Count -gt 0) {
    if ($commitBodyLines.Count -gt 0) {
        $commitBodyLines.Add('')
    }
    foreach ($change in $Changes) {
        if (-not [string]::IsNullOrWhiteSpace($change)) {
            $commitBodyLines.Add("- $($change.Trim())")
        }
    }
}
$commitBody = ($commitBodyLines -join [Environment]::NewLine).Trim()

$baseTag = Get-LatestSemVerTag
$packageData = Get-Content -LiteralPath 'package.json' -Raw | ConvertFrom-Json
$currentVersion = [string] $packageData.version
if ("v$currentVersion" -ne $baseTag) {
    throw "A versão do package.json ($currentVersion) não corresponde à última tag ($baseTag). Corrija a inconsistência antes de publicar."
}

$commitsBeforeRelease = @(Get-CommitRecords -BaseTag $baseTag)
$pendingCommit = [PSCustomObject]@{
    Hash    = 'pending'
    Subject = $CommitMessage
    Body    = $commitBody
}
$commitsForBump = @($commitsBeforeRelease) + @($pendingCommit)

$selectedBump = if ($Bump -eq 'Auto') {
    Get-AutomaticBump -Commits $commitsForBump
} else {
    $Bump
}

$newVersion = Get-NextVersion -BaseTag $baseTag -SelectedBump $selectedBump
$newTag = "v$newVersion"

$localTagCheck = Invoke-Git -Arguments @('tag', '--list', $newTag)
if (@($localTagCheck.Output | Where-Object { $_.Trim() -eq $newTag }).Count -gt 0) {
    throw "A tag $newTag já existe localmente."
}

$remoteTagCheck = Invoke-Git -Arguments @('ls-remote', '--exit-code', '--tags', 'origin', "refs/tags/$newTag") -AllowFailure
if ($remoteTagCheck.ExitCode -eq 0) {
    throw "A tag $newTag já existe no GitHub."
}
if ($remoteTagCheck.ExitCode -ne 2) {
    throw 'Não foi possível verificar as tags remotas.'
}

Write-Step "Atualizando versão para $newVersion"
Invoke-Npm -Arguments @('version', $newVersion, '--no-git-tag-version')
Write-Ok 'package.json e package-lock.json atualizados'

Write-Step 'Preparando commit'
$filesToAdd = @($normalizedFiles + @('package.json', 'package-lock.json') | Sort-Object -Unique | Where-Object {
    if (Test-Path -LiteralPath $_) {
        return $true
    }

    $indexCheck = Invoke-Git -Arguments @('ls-files', '--error-unmatch', '--', $_) -AllowFailure
    return $indexCheck.ExitCode -eq 0
})

if (@($filesToAdd).Count -gt 0) {
    Invoke-Git -Arguments (@('add', '--') + $filesToAdd) | Out-Null
}

$stagedCheck = Invoke-Git -Arguments @('diff', '--cached', '--quiet') -AllowFailure
if ($stagedCheck.ExitCode -eq 0) {
    throw 'Nenhuma alteração foi adicionada ao staging.'
}
if ($stagedCheck.ExitCode -ne 1) {
    throw 'Não foi possível validar o staging.'
}

$stagedFiles = @((Invoke-Git -Arguments @('diff', '--cached', '--name-only', '--diff-filter=ACMR')).Output | ForEach-Object {
    Normalize-GitPath $_
})

if (-not $SkipValidation) {
    Invoke-FileValidations -StagedFiles $stagedFiles
} else {
    Write-Warn 'Validações automáticas foram ignoradas por -SkipValidation.'
}

Write-Step "Gerando instalador do MPTreco $newVersion"
Invoke-Npm -Arguments @('run', 'dist')

$installerRelativePath = "dist/MPTreco-Setup-$newVersion.exe"
if (-not (Test-Path -LiteralPath $installerRelativePath -PathType Leaf)) {
    throw "A build terminou sem gerar o instalador esperado: $installerRelativePath"
}
if ((Get-Item -LiteralPath $installerRelativePath).Length -le 0) {
    throw "O instalador gerado está vazio: $installerRelativePath"
}
Write-Ok "Instalador validado: $installerRelativePath"

$blockmapRelativePath = "$installerRelativePath.blockmap"
$metadataRelativePath = 'dist/latest.yml'
foreach ($updateFile in @($blockmapRelativePath, $metadataRelativePath)) {
    if (-not (Test-Path -LiteralPath $updateFile -PathType Leaf)) {
        throw "Arquivo de atualização não foi gerado: $updateFile"
    }
    if ((Get-Item -LiteralPath $updateFile).Length -le 0) {
        throw "Arquivo de atualização está vazio: $updateFile"
    }
    Write-Ok "Arquivo de atualização validado: $updateFile"
}

$updateMetadata = Get-Content -LiteralPath $metadataRelativePath -Raw
if ($updateMetadata -notmatch "(?m)^version:\s*$([regex]::Escape($newVersion))\s*$") {
    throw 'A versão em latest.yml não corresponde à nova versão.'
}
if (-not $updateMetadata.Contains("MPTreco-Setup-$newVersion.exe")) {
    throw 'O latest.yml não aponta para o instalador gerado.'
}

$commitArguments = @('commit', '-m', $CommitMessage)
if (-not [string]::IsNullOrWhiteSpace($commitBody)) {
    $commitArguments += @('-m', $commitBody)
}
Invoke-Git -Arguments $commitArguments | Out-Null
Write-Ok "Commit criado: $CommitMessage"

$commits = @(Get-CommitRecords -BaseTag $baseTag)
if (@($commits).Count -eq 0) {
    throw 'Nenhum commit novo foi encontrado após a última tag.'
}

$emDash = [char]0x2014
$fullTitle = "MPTRECO $newTag $emDash $($ReleaseTitle.Trim())"
$releaseNotesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("mptreco-release-$newTag.md")

Write-Step 'Gerando descrição oficial da Release'

$releaseLines = New-Object System.Collections.Generic.List[string]
$releaseLines.Add("# $fullTitle")
$releaseLines.Add('')

if (-not [string]::IsNullOrWhiteSpace($Description)) {
    $releaseLines.Add($Description.Trim())
} else {
    $releaseLines.Add("Publicação oficial do MPTreco gerada automaticamente a partir dos commits posteriores a $baseTag.")
}
$releaseLines.Add('')
$releaseLines.Add('> Esta versão foi classificada automaticamente como **' + $selectedBump.ToUpperInvariant() + '** com base no padrão Conventional Commits.')
$releaseLines.Add('')

$breakingCommits = @($commits | Where-Object {
    $_.Subject -match '^[a-zA-Z]+(\([^)]+\))?!:' -or "$($_.Subject)`n$($_.Body)" -match '(?im)^BREAKING[ -]CHANGE:\s*\S'
})
$featureCommits = @($commits | Where-Object { (Get-CommitType $_.Subject) -eq 'feat' -and $breakingCommits -notcontains $_ })
$fixCommits = @($commits | Where-Object { (Get-CommitType $_.Subject) -eq 'fix' -and $breakingCommits -notcontains $_ })
$securityCommits = @($commits | Where-Object { (Get-CommitType $_.Subject) -eq 'security' -and $breakingCommits -notcontains $_ })
$performanceCommits = @($commits | Where-Object { (Get-CommitType $_.Subject) -eq 'perf' -and $breakingCommits -notcontains $_ })
$improvementCommits = @($commits | Where-Object {
    (Get-CommitType $_.Subject) -in @('refactor', 'style') -and $breakingCommits -notcontains $_
})
$maintenanceCommits = @($commits | Where-Object {
    (Get-CommitType $_.Subject) -in @('docs', 'test', 'build', 'ci', 'chore', 'other') -and $breakingCommits -notcontains $_
})

Add-CommitSection -Lines $releaseLines -Heading 'Mudanças incompatíveis' -Commits $breakingCommits
Add-CommitSection -Lines $releaseLines -Heading 'Novidades' -Commits $featureCommits
Add-CommitSection -Lines $releaseLines -Heading 'Correções' -Commits $fixCommits
Add-CommitSection -Lines $releaseLines -Heading 'Segurança' -Commits $securityCommits
Add-CommitSection -Lines $releaseLines -Heading 'Desempenho' -Commits $performanceCommits
Add-CommitSection -Lines $releaseLines -Heading 'Melhorias internas e de interface' -Commits $improvementCommits
Add-CommitSection -Lines $releaseLines -Heading 'Documentação, build e manutenção' -Commits $maintenanceCommits

$changedSinceTag = if ($baseTag -eq 'v0.0.0') {
    @((Invoke-Git -Arguments @('ls-tree', '-r', '--name-only', 'HEAD')).Output)
} else {
    @((Invoke-Git -Arguments @('diff', '--name-only', "$baseTag..HEAD")).Output)
}
$changedSinceTag = @($changedSinceTag | ForEach-Object { Normalize-GitPath $_ } | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
})

$releaseLines.Add('## Arquivos alterados')
$releaseLines.Add('')
foreach ($file in $changedSinceTag) {
    $releaseLines.Add('- `' + $file + '`')
}
$releaseLines.Add('')

$releaseLines.Add('## Instalação')
$releaseLines.Add('')
$releaseLines.Add('1. Baixe o instalador `MPTreco-Setup-' + $newVersion + '.exe` anexado a esta Release.')
$releaseLines.Add('2. Feche qualquer instância aberta do MPTreco.')
$releaseLines.Add('3. Execute o instalador e conclua a atualização.')
$releaseLines.Add('')

$releaseLines.Add('## Comparação')
$releaseLines.Add('')
$releaseLines.Add('`' + $baseTag + '...' + $newTag + '`')
$releaseLines.Add('')
$releaseLines.Add('---')
$releaseLines.Add('')
$releaseLines.Add('Release gerada pelo fluxo oficial de versionamento do MPTreco.')

Write-Utf8NoBom -Path $releaseNotesFile -Lines ($releaseLines.ToArray())
Write-Ok 'Notas geradas e prontas para a tag anotada'

$pendingAfterCommit = @(Get-ChangedFiles)
if (@($pendingAfterCommit).Count -gt 0) {
    $pendingList = ($pendingAfterCommit | ForEach-Object { " - $_" }) -join "`n"
    throw "O repositório não ficou limpo após preparar a versão:`n$pendingList"
}

$finalCommit = Get-GitText @('rev-parse', '--short=8', 'HEAD')

Write-Host ''
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host ' PUBLICAÇÃO OFICIAL DO MPTRECO' -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host "Versão anterior : $baseTag"
Write-Host "Incremento      : $selectedBump"
Write-Host "Nova versão     : $newTag" -ForegroundColor Green
Write-Host "Commit          : $finalCommit"
Write-Host "Título          : $fullTitle"
Write-Host "Instalador local: $installerRelativePath"
Write-Host 'Notas           : incorporadas à tag anotada'
Write-Host "Commits incluídos: $(@($commits).Count)"
Write-Host '=============================================' -ForegroundColor DarkCyan

if (-not $NoConfirm) {
    $confirmation = Read-Host 'Confirmar push da main, criação da tag e publicação automática da Release? [S/N]'
    if ($confirmation -notmatch '^(s|sim|y|yes)$') {
        Remove-Item -LiteralPath $releaseNotesFile -Force -ErrorAction SilentlyContinue
        Write-Warn 'Publicação cancelada antes do push. O commit permanece apenas no repositório local.'
        exit 0
    }
}

Write-Step 'Enviando commit para origin/main'
Invoke-Git -Arguments @('push', 'origin', 'main') | Out-Null
Write-Ok 'Commit enviado para origin/main'

Write-Step "Criando tag anotada $newTag"
Invoke-Git -Arguments @('tag', '-a', $newTag, '-F', $releaseNotesFile) | Out-Null
Write-Ok "Tag local criada: $newTag"

Write-Step "Enviando tag $newTag para o GitHub"
$tagPush = Invoke-Git -Arguments @('push', 'origin', $newTag) -AllowFailure
if ($tagPush.ExitCode -ne 0) {
    $details = (@($tagPush.Output) + @($tagPush.ErrorOutput) | Out-String).Trim()
    throw "O commit foi enviado e a tag foi criada localmente, mas o push da tag falhou.`n$details`nApós corrigir a conexão, execute: git push origin $newTag"
}
Write-Ok "Tag enviada: $newTag"

Remove-Item -LiteralPath $releaseNotesFile -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "VERSÃO OFICIAL PUBLICADA: $newTag" -ForegroundColor Green
Write-Host 'O GitHub Actions gerará uma build limpa e anexará o instalador à Release.' -ForegroundColor Green
Write-Host 'Acompanhe em: GitHub > Actions > Publicar Release Oficial'
Write-Host ''
