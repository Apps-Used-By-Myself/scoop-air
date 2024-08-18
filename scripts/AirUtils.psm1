function WriteLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formattedMessage = "`n[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Info' {
            Write-Information -MessageData $formattedMessage -InformationAction Continue
        }
        'Warning' {
            Write-Warning -Message $formattedMessage
        }
        'Error' {
            Write-Error -Message $formattedMessage -ErrorAction Continue
        }
    }
}

function IsDirectoryEmpty {
    [CmdletBinding()]
    param ([string]$Path)

    $item = Get-Item $Path -Force
    return [string]::IsNullOrEmpty($item.GetFiles("*", [System.IO.SearchOption]::AllDirectories)) -and
    [string]::IsNullOrEmpty($item.GetDirectories("*", [System.IO.SearchOption]::AllDirectories))
}

function EnsureFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    process {
        foreach ($path in $Paths) {
            if (!(Test-Path -Path $path -PathType Leaf)) {
                New-Item -ItemType File -Path $path -Force | Out-Null
            }
        }
    }
}

function EnsureDir {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    process {
        foreach ($path in $Paths) {
            if (!(Test-Path -Path $path -PathType Container)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }
}

function WriteFile {
    [CmdletBinding()]
    param (
        [string]$FilePath,
        [string]$Content,
        [string]$Encoding = 'UTF8'
    )

    $directory = Split-Path -Path $FilePath -Parent
    EnsureDir -DirectoryPath $directory
    Set-Content -Path $FilePath -Value $Content -Encoding $Encoding -Force
}

function RedirectDir {
    [CmdletBinding()]
    param (
        [string]$DataDir,
        [string]$PersistDir
    )

    if (Test-Path $DataDir) {
        $item = Get-Item $DataDir -Force
        if ($item.LinkType -and $item.Target -eq $PersistDir) {
            WriteLog """$DataDir"" is already linked to ""$PersistDir""." -Level 'Warning'
            return
        }

        if ($item.LinkType) {
            WriteLog """$DataDir"" is already a link. Exiting script." -Level 'Warning'
            exit
        }
    }

    EnsureDir -DirectoryPath $PersistDir

    if (!(Test-Path $DataDir)) {
        New-Item -ItemType Junction -Path $DataDir -Target $PersistDir | Out-Null
        WriteLog "Created junction from ""$DataDir"" to ""$PersistDir""." -Level 'Info'
        return
    }

    $dataEmpty = IsDirectoryEmpty $DataDir
    $persistEmpty = IsDirectoryEmpty $PersistDir

    if (!$dataEmpty -and $persistEmpty) {
        #/E：复制子目录，包括空目录
        # /MOVE：移动文件（复制后删除源）
        # /NFL：不记录文件名
        # /NDL：不记录目录名
        # /NJH：不显示作业头
        # /NJS：不显示作业摘要
        # /NC：不记录文件类别
        # /NS：不记录文件大小
        # /NP：不显示进度百分比
        robocopy $DataDir $PersistDir /E /MOVE /NFL /NDL /NJH /NJS /NC /NS | Out-Null
        WriteLog "Moved contents from ""$DataDir"" to ""$PersistDir""." -Level 'Info'
    }
    elseif (!$dataEmpty -and !$persistEmpty) {
        $backupName = "{0}-backup-{1}" -f $DataDir, (Get-Date -Format "yyMMddHHmmss")
        Rename-Item -Path $DataDir -NewName $backupName
        WriteLog "Both directories contain data. ""$DataDir"" backed up to $backupName." -Level 'Warning'
    }

    if (Test-Path $DataDir) {
        Remove-Item $DataDir -Force -Recurse
    }

    New-Item -ItemType Junction -Path $DataDir -Target $PersistDir | Out-Null
    WriteLog "Created junction from ""$DataDir"" to ""$PersistDir""." -Level 'Info'
}

function RemoveJunction {
    param ([string]$Path)

    if (Test-Path $Path -PathType Container) {
        $item = Get-Item $Path -Force
        if ($item.LinkType -eq "Junction") {
            Remove-Item $Path -Force
        }
    }
}

Export-ModuleMember -Function WriteLog, IsDirectoryEmpty, EnsureFile, EnsureDir, WriteFile, RedirectDir, RemoveJunction
