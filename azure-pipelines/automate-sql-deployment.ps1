$base = "release/deployment-july-2025-sale"
$target = "release/deployment-september-2025-sale"

git fetch origin

$diffs = git diff --name-status origin/$base..origin/$target -- '*.sql'

Write-Host "Processing Schema Changes"
foreach ($line in $diffs) {
    $status, $file = $line -split "`t"
    # Only process if the file is from the SchemaChanges folder
    if ($file -match "dbo/Tables/SchemaChanges") {
        $fileName = [System.IO.Path]::GetFileName($file)
        
        if ($status -eq "A") {
            git show "origin/${target}:${file}" > tmp_schema.txt
            $schemaContent = Get-Content tmp_schema.txt -Raw
            
            # Check if file ends with _Rollback suffix
            if ($fileName -match "_Rollback\.sql$") {
                # This is a rollback file, add to rollback script
                Add-Content -Path "NewAdmin_Rollback.sql" -Value $schemaContent -Encoding utf8NoBOM
            }
            else {
                # This is an apply file, add to apply script
                Add-Content -Path "NewAdmin_Apply.sql" -Value $schemaContent -Encoding utf8NoBOM
            }
        }
    }
}


Write-Host "Processing Stored Procedures changes"
foreach ($line in $diffs) {
    $status, $file = $line -split "`t"
    # Only process if the file is from the Stored Procedures folder
    if ($file -match "dbo/Stored Procedures") {
        if ($status -eq "A") {
            git show "origin/${target}:${file}" > tmp_apply.txt
            "DROP PROCEDURE [$([System.IO.Path]::GetFileNameWithoutExtension($file))];" > tmp_rollback.txt
        } elseif ($status -eq "M") {
            git show "origin/${target}:${file}" > tmp_apply.txt
            git show "origin/${base}:${file}" > tmp_rollback.txt
            
        } elseif ($status -eq "D") {
            "DROP PROCEDURE [$([System.IO.Path]::GetFileNameWithoutExtension($file))];" > tmp_apply.txt
            git show "origin/${base}:${file}" > tmp_rollback.txt
        }

        $apply = Get-Content tmp_apply.txt -Raw
        $rollback = Get-Content tmp_rollback.txt -Raw
        
        # For rollback, replace CREATE PROCEDURE with ALTER PROCEDURE and ensure GO at the end
        $apply = $apply -replace 'CREATE PROCEDURE', 'CREATE OR ALTER PROCEDURE'
        $apply = $apply.TrimEnd()
        if (-not $apply.EndsWith("GO")) {
            $apply = $apply + "`nGO"
        }
        $rollback = $rollback -replace 'CREATE PROCEDURE', 'CREATE OR ALTER PROCEDURE'
        $rollback = $rollback.TrimEnd()
        if (-not $rollback.EndsWith("GO")) {
            $rollback = $rollback + "`nGO"
        }

        Add-Content -Path "NewAdmin_Apply.sql" -Value $apply -Encoding utf8NoBOM
        Add-Content -Path "NewAdmin_Rollback.sql" -Value $rollback -Encoding utf8NoBOM
    }
}

Write-Host "Processing Views changes"
foreach ($line in $diffs) {
    $status, $file = $line -split "`t"
    # Only process if the file is from the Stored Procedures folder
    if ($file -match "dbo/Views") {
        if ($status -eq "A") {
            git show "origin/${target}:${file}" > tmp_apply.txt
            "DROP VIEW [$([System.IO.Path]::GetFileNameWithoutExtension($file))];" > tmp_rollback.txt
        }
        elseif ($status -eq "M") {
            git show "origin/${target}:${file}" > tmp_apply.txt
            git show "origin/${base}:${file}" > tmp_rollback.txt
            
        }
        elseif ($status -eq "D") {
            "DROP VIEW [$([System.IO.Path]::GetFileNameWithoutExtension($file))];" > tmp_apply.txt
            git show "origin/${base}:${file}" > tmp_rollback.txt
        }

        $apply = Get-Content tmp_apply.txt -Raw
        $rollback = Get-Content tmp_rollback.txt -Raw
        
        # For rollback, replace CREATE PROCEDURE with ALTER PROCEDURE and ensure GO at the end
        $apply = $apply -replace 'CREATE VIEW', 'CREATE OR ALTER VIEW'
        $apply = $apply.TrimEnd()
        if (-not $apply.EndsWith("GO")) {
            $apply = $apply + "`nGO"
        }
        $rollback = $rollback -replace 'CREATE VIEW', 'CREATE OR ALTER VIEW'
        $rollback = $rollback.TrimEnd()
        if (-not $rollback.EndsWith("GO")) {
            $rollback = $rollback + "`nGO"
        }

        Add-Content -Path "NewAdmin_Apply.sql" -Value $apply -Encoding utf8NoBOM
        Add-Content -Path "NewAdmin_Rollback.sql" -Value $rollback -Encoding utf8NoBOM
    }
}