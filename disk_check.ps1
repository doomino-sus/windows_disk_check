#
# Skrypt: Get-DiskInfo.ps1
# Data: 2024
#
# Ten skrypt zbiera i wyświetla szczegółowe informacje o wszystkich dyskach fizycznych
# podłączonych do komputera, wraz z informacjami o ich partycjach, wykorzystaniu przestrzeni
# oraz szczegółową analizą żywotności dysku w skali 0-100%.

# Funkcja do formatowania rozmiaru w czytelny format
function Format-Size {
    param([int64]$Size)
    
    $suffixes = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $i = 0
    
    while ($Size -ge 1024 -and $i -lt $suffixes.Length - 1) {
        $Size = $Size / 1024
        $i++
    }
    
    return "{0:N2} {1}" -f $Size, $suffixes[$i]
}

# Funkcja do tworzenia paska postępu
function Show-DiskUsageBar {
    param(
        [Parameter(Mandatory=$true)]
        [double]$Percentage,
        [int]$Width = 20
    )
    
    $filled = [math]::Round(($Percentage / 100) * $Width)
    $empty = $Width - $filled
    
    $bar = "[" + ("█" * $filled) + ("-" * $empty) + "]"
    return $bar
}

# Funkcja do obliczania żywotności dysku
function Get-DiskHealth {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Disk
    )
    
    try {
        # Pobieranie szczegółowych informacji o dysku
        $smartData = $Disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        
        Write-Verbose "Analizowanie danych SMART dla dysku $($Disk.FriendlyName)"
        
        if ($smartData) {
            Write-Verbose "Znaleziono dane SMART:"
            Write-Verbose "  Temperatura: $($smartData.Temperature)°C"
            Write-Verbose "  Błędy odczytu: $($smartData.ReadErrorsTotal)"
            Write-Verbose "  Błędy zapisu: $($smartData.WriteErrorsTotal)"
            Write-Verbose "  Czas pracy: $($smartData.PowerOnHours) godzin"
            # Obliczanie żywotności na podstawie różnych parametrów
            $wearFactors = @{
                Temperature = if ($smartData.Temperature -gt 0) { 
                    [math]::Max(0, 100 - [math]::Max(0, ($smartData.Temperature - 30) * 2)) 
                } else { 100 }
                ReadErrors = if ($smartData.ReadErrorsTotal -gt 0) {
                    [math]::Max(0, 100 - [math]::Log($smartData.ReadErrorsTotal + 1, 2) * 10)
                } else { 100 }
                WriteErrors = if ($smartData.WriteErrorsTotal -gt 0) {
                    [math]::Max(0, 100 - [math]::Log($smartData.WriteErrorsTotal + 1, 2) * 10)
                } else { 100 }
                PowerOnHours = if ($smartData.PowerOnHours -gt 0) {
                    [math]::Max(0, 100 - ($smartData.PowerOnHours / 8760) * 10) # 8760 to liczba godzin w roku
                } else { 100 }
            }
            
            # Obliczanie średniej ważonej
            $healthScore = ($wearFactors.Temperature * 0.3 + 
                          $wearFactors.ReadErrors * 0.25 +
                          $wearFactors.WriteErrors * 0.25 +
                          $wearFactors.PowerOnHours * 0.2)
            
            return [math]::Round($healthScore, 2)
        }
        
        # Jeśli nie ma danych SMART, bazujemy na podstawowym statusie dysku
        $baseHealth = switch ($Disk.HealthStatus) {
            "Healthy" { 100 }
            "Warning" { 50 }
            "Unhealthy" { 10 }
            default { 0 }
        }
        
        return $baseHealth
    }
    catch {
        Write-Warning "Nie można obliczyć szczegółowej żywotności dysku. Używam podstawowego statusu."
        return 0
    }
}

# Główna część skryptu
try {
    Clear-Host
    Write-Host "=== Informacje o dyskach fizycznych ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Sprawdzanie czy cmdlet Get-PhysicalDisk jest dostępny
    if (-not (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        Write-Host "UWAGA: Cmdlet Get-PhysicalDisk nie jest dostępny w tym środowisku." -ForegroundColor Yellow
        Write-Host "Możliwe przyczyny:" -ForegroundColor Yellow
        Write-Host "1. Skrypt jest uruchomiony w środowisku wirtualnym (np. Replit)"
        Write-Host "2. Brak wymaganych uprawnień administratora"
        Write-Host "3. Moduł Storage nie jest zainstalowany"
        Write-Host "`nInformacje o środowisku:" -ForegroundColor Cyan
        Write-Host "System: $($PSVersionTable.OS)"
        Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
        exit 0
    }
    
    # Pobieranie informacji o dyskach fizycznych
    $physicalDisks = Get-PhysicalDisk | Sort-Object DeviceId
    
    foreach ($disk in $physicalDisks) {
        # Nagłówek dla każdego dysku
        Write-Host ("Dysk {0}: {1}" -f $disk.DeviceId, $disk.FriendlyName) -ForegroundColor Yellow
        Write-Host ("Status: {0}" -f $disk.OperationalStatus) -ForegroundColor $(if ($disk.OperationalStatus -eq "OK") {"Green"} else {"Red"})
        Write-Host ("Typ mediów: {0}" -f $disk.MediaType)
        Write-Host ("Rozmiar całkowity: {0}" -f (Format-Size $disk.Size))
        Write-Host ("Model: {0}" -f $disk.Model)
        Write-Host ("Interfejs: {0}" -f $disk.BusType)
        Write-Host ("Numer seryjny: {0}" -f $disk.SerialNumber)
        Write-Host ("Stan zdrowia: {0}" -f $disk.HealthStatus) -ForegroundColor $(if ($disk.HealthStatus -eq "Healthy") {"Green"} else {"Red"})
        
        # Obliczanie i wyświetlanie żywotności dysku
        $diskHealth = Get-DiskHealth -Disk $disk
        $healthColor = if ($diskHealth -ge 80) {
            "Green"
        } elseif ($diskHealth -ge 60) {
            "Yellow"
        } elseif ($diskHealth -ge 40) {
            "DarkYellow"
        } elseif ($diskHealth -ge 20) {
            "Red"
        } else {
            "DarkRed"
        }
        Write-Host "`nAnaliza żywotności dysku:" -ForegroundColor Cyan
        Write-Host ("Całkowita ocena żywotności: {0}%" -f $diskHealth) -ForegroundColor $healthColor
        Write-Host ("  " + (Show-DiskUsageBar $diskHealth))
        
        # Wyświetlanie szczegółowych informacji o składowych żywotności
        if ($smartData) {
            Write-Host "`nSkładowe oceny żywotności:" -ForegroundColor Cyan
            Write-Host ("  Temperatura: {0}°C" -f $smartData.Temperature)
            Write-Host ("  Całkowite błędy odczytu: {0}" -f $smartData.ReadErrorsTotal)
            Write-Host ("  Całkowite błędy zapisu: {0}" -f $smartData.WriteErrorsTotal)
            Write-Host ("  Czas pracy: {0} godzin" -f $smartData.PowerOnHours)
        }
        
        # Pobieranie partycji dla danego dysku
        $partitions = Get-Partition | Where-Object DiskNumber -eq $disk.DeviceId
        
        if ($partitions) {
            Write-Host "`nPartycje:" -ForegroundColor Green
            
            foreach ($partition in $partitions) {
                # Pobieranie informacji o wolumenie
                $volume = Get-Volume -Partition $partition -ErrorAction SilentlyContinue
                
                if ($volume) {
                    $usedSpace = $volume.Size - $volume.SizeRemaining
                    $percentUsed = [math]::Round(($usedSpace / $volume.Size) * 100)
                    
                    Write-Host ("`nPartycja {0}:" -f $partition.PartitionNumber)
                    Write-Host ("  Litera dysku: {0}" -f $volume.DriveLetter)
                    Write-Host ("  Etykieta: {0}" -f $volume.FileSystemLabel)
                    Write-Host ("  System plików: {0}" -f $volume.FileSystem)
                    Write-Host ("  Rozmiar: {0}" -f (Format-Size $volume.Size))
                    Write-Host ("  Wolne miejsce: {0}" -f (Format-Size $volume.SizeRemaining))
                    Write-Host ("  Wykorzystane: {0}%" -f $percentUsed)
                    Write-Host ("  " + (Show-DiskUsageBar $percentUsed))
                }
            }
        } else {
            Write-Host "`nBrak partycji na tym dysku." -ForegroundColor Red
        }
        
        Write-Host "`n" + ("-" * 50) + "`n"
    }
}
catch {
    Write-Host "`nWystąpił błąd podczas zbierania informacji o dyskach:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Szczegóły błędu:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    # Sugestie rozwiązania problemu
    Write-Host "`nMożliwe rozwiązania:" -ForegroundColor Yellow
    Write-Host "1. Upewnij się, że masz uprawnienia administratora"
    Write-Host "2. Sprawdź, czy wszystkie dyski są podłączone prawidłowo"
    Write-Host "3. Spróbuj uruchomić skrypt ponownie"
}
finally {
    # Wyświetlamy prosty komunikat o zakończeniu bez oczekiwania na klawisz
    Write-Host "`nKoniec działania skryptu." -ForegroundColor Cyan
    exit 0  # Zakończenie skryptu z kodem 0 (sukces)
}
