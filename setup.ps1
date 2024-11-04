if ($null -eq (Get-Command "sops" -ErrorAction SilentlyContinue)) {
    choco install make -y
} else {
    Write-Host "'sops' already installed"
}

if ($null -eq (Get-Command "az" -ErrorAction SilentlyContinue)) {
    choco install make -y
} else {
    Write-Host "'azure-cli' already installed"
}

az login --tenant "00c55417-714c-4a52-89e7-0fd917787341"

$folder=".\secrets"
$filetypes="*.enc.*"

Get-ChildItem $folder -Filter $filetypes | Foreach-Object {
   
    $filepath=$_.FullName
    $unencryptedPath = $filepath.Replace('.enc.','.')
    
    Write-Host "Decrypting $filepath into $unencryptedPath"
    try {
        sops -d "$filepath" | Out-File -Encoding "default" -FilePath "$unencryptedPath" 
    }
    catch {
        Write-Host "Failed to decrypt $filepath into $unencryptedPath"
    }
}