param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('send', 'receive')]
    [string]$Mode,

    [string]$RelayDir = $env:CLIPBOARD_RELAY_DIR,

    [string]$InputText,

    [string[]]$InputPaths,

    [switch]$NoClipboard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hasInputText = $PSBoundParameters.ContainsKey('InputText')
$hasInputPaths = $PSBoundParameters.ContainsKey('InputPaths')

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Resolve-RelayRoot {
    if ([string]::IsNullOrWhiteSpace($RelayDir)) {
        throw 'Set CLIPBOARD_RELAY_DIR or pass -RelayDir.'
    }

    $resolved = [System.IO.Path]::GetFullPath($RelayDir)
    return $resolved.TrimEnd('\')
}

function New-ItemId {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $suffix = -join ((48..57) + (97..102) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    return "$stamp-$suffix"
}

function Get-ClipboardText {
    if ($script:hasInputText) {
        return $script:InputText
    }

    try {
        return Get-Clipboard -Raw -Format Text -ErrorAction Stop
    } catch {
        return $null
    }
}

function Normalize-PathList {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items
    )

    $normalized = @()
    foreach ($item in $Items) {
        if ($null -eq $item) {
            continue
        }

        if (($item -is [System.Collections.IEnumerable]) -and -not ($item -is [string])) {
            $normalized += Normalize-PathList -Items @($item)
            continue
        }

        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $parts = $text -split '\r?\n'
        foreach ($part in $parts) {
            if (-not [string]::IsNullOrWhiteSpace($part)) {
                $normalized += [string]$part
            }
        }
    }

    return $normalized
}

function Get-ClipboardPaths {
    if ($script:hasInputPaths) {
        return @(Normalize-PathList -Items @($script:InputPaths))
    }

    try {
        return @(Normalize-PathList -Items @(Get-Clipboard -Format FileDropList -ErrorAction Stop))
    } catch {
        return @()
    }
}

function Copy-ItemSafely {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Destination)
        $ext = [System.IO.Path]::GetExtension($Destination)
        $parent = Split-Path -Parent $Destination
        $index = 1
        do {
            $Destination = Join-Path $parent ("{0}-{1}{2}" -f $base, $index, $ext)
            $index++
        } while (Test-Path -LiteralPath $Destination)
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Save-Manifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Manifest
    )

    $json = $Manifest | ConvertTo-Json -Depth 10
    Write-Utf8NoBom -Path $Path -Content $json
}

function Read-Manifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Resolve-RelayPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelayRoot,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        return $RelativePath
    }

    return Join-Path $RelayRoot $RelativePath
}

function Clear-RelayItems {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ItemsRoot
    )

    if (-not (Test-Path -LiteralPath $ItemsRoot)) {
        return
    }

    foreach ($child in Get-ChildItem -LiteralPath $ItemsRoot -Force) {
        try {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            # OneDrive and other sync clients can hold reparse points or files open briefly.
            # Cleanup is best-effort so a send can still complete and advance latest.json.
        }
    }
}

function Get-ClipboardDisplayLabel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [string[]]$Names = @()
    )

    if ($Type -eq 'files') {
        if ($Names.Count -eq 1) {
            return $Names[0]
        }

        if ($Names.Count -gt 1) {
            return ('{0} files: {1}' -f $Names.Count, ($Names -join ', '))
        }

        return '[clipboard files]'
    }

    return '[clipboard text]'
}
function Send-Clipboard {
    $relayRoot = Resolve-RelayRoot
    $itemsRoot = Join-Path $relayRoot 'items'
    New-Item -ItemType Directory -Force -Path $itemsRoot | Out-Null
    Clear-RelayItems -ItemsRoot $itemsRoot

    $itemId = New-ItemId
    $itemDir = Join-Path $itemsRoot $itemId
    New-Item -ItemType Directory -Force -Path $itemDir | Out-Null

    $machine = $env:COMPUTERNAME
    $copiedNames = @()
    $manifest = $null

    $paths = @()
    if ($script:hasInputPaths) {
        $paths = @(Get-ClipboardPaths)
    } elseif (-not $NoClipboard) {
        $paths = @(Get-ClipboardPaths)
    }
    if ($paths.Count -gt 0) {
        $staging = Join-Path $env:TEMP ("clipboard-relay-{0}" -f $itemId)
        New-Item -ItemType Directory -Force -Path $staging | Out-Null

        foreach ($path in $paths) {
            $source = [string]$path
            $leaf = [System.IO.Path]::GetFileName($source.TrimEnd('\'))
            if ([string]::IsNullOrWhiteSpace($leaf)) {
                $leaf = [System.IO.Path]::GetFileName($source)
            }

            $target = [System.IO.Path]::Combine($staging, $leaf)
            Copy-ItemSafely -Source $source -Destination $target
            $copiedNames += $leaf
        }

        $archive = Join-Path $itemDir 'payload.zip'
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archive -Force
        Remove-Item -LiteralPath $staging -Recurse -Force

        $manifest = [ordered]@{
            version       = 1
            id            = $itemId
            createdUtc    = (Get-Date).ToUniversalTime().ToString('o')
            type          = 'files'
            payloadFile   = 'payload.zip'
            sourceMachine = $machine
            names         = $copiedNames
        }
    } else {
        if ($NoClipboard -and -not $script:hasInputText) {
            throw 'Use -InputText or -InputPaths when -NoClipboard is set.'
        }

        $text = if ($NoClipboard) { $script:InputText } else { Get-ClipboardText }
        if ($null -eq $text) {
            throw 'Clipboard is empty or unavailable.'
        }

        $payload = Join-Path $itemDir 'payload.txt'
        Write-Utf8NoBom -Path $payload -Content $text

        $manifest = [ordered]@{
            version       = 1
            id            = $itemId
            createdUtc    = (Get-Date).ToUniversalTime().ToString('o')
            type          = 'text'
            payloadFile   = 'payload.txt'
            sourceMachine = $machine
        }
    }

    Save-Manifest -Path (Join-Path $itemDir 'manifest.json') -Manifest $manifest

    $latest = [ordered]@{
        itemId     = $itemId
        itemDir    = "items/$itemId"
        manifest   = "items/$itemId/manifest.json"
        createdUtc = $manifest.createdUtc
        type       = $manifest.type
    }
    Save-Manifest -Path (Join-Path $relayRoot 'latest.json') -Manifest $latest

    [pscustomobject]@{
        action = 'send'
        item = Get-ClipboardDisplayLabel -Type $manifest.type -Names $copiedNames
        type = $manifest.type
    }
}

function Receive-Clipboard {
    $relayRoot = Resolve-RelayRoot
    $latestPath = Join-Path $relayRoot 'latest.json'
    if (-not (Test-Path -LiteralPath $latestPath)) {
        throw "No latest.json found in relay root: $relayRoot"
    }

    $latest = Read-Manifest -Path $latestPath
    $manifestPath = Resolve-RelayPath -RelayRoot $relayRoot -RelativePath ([string]$latest.manifest)
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Manifest not found: $manifestPath"
    }

    $manifest = Read-Manifest -Path $manifestPath
    $itemDir = Split-Path -Parent $manifestPath
    $payloadPath = Join-Path $itemDir $manifest.payloadFile
    if (-not (Test-Path -LiteralPath $payloadPath)) {
        throw "Payload not found: $payloadPath"
    }

    if ($manifest.type -eq 'text') {
        $text = Get-Content -LiteralPath $payloadPath -Raw
        if (-not $NoClipboard) {
            Set-Clipboard -Value $text
        }

        return [pscustomobject]@{
            action = 'receive'
            itemId = $manifest.id
            type = $manifest.type
            clipboardWritten = (-not $NoClipboard)
            textLength = $text.Length
        }
    }

    $extractRoot = Join-Path $env:TEMP ("clipboard-relay-restore-{0}" -f $manifest.id)
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    Expand-Archive -LiteralPath $payloadPath -DestinationPath $extractRoot -Force

    $restoredPaths = @(
        Get-ChildItem -LiteralPath $extractRoot -Force | Select-Object -ExpandProperty FullName
    )

    if (-not $NoClipboard) {
        Set-Clipboard -Path $restoredPaths
    }

    return [pscustomobject]@{
        action = 'receive'
        itemId = $manifest.id
        type = $manifest.type
        clipboardWritten = (-not $NoClipboard)
        restoredCount = $restoredPaths.Count
        extractRoot = $extractRoot
    }
}

switch ($Mode) {
    'send' { Send-Clipboard }
    'receive' { Receive-Clipboard }
}

