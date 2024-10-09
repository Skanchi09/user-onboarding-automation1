param( 
    [string]$filePath = "",        # CSV file input (optional, positional)
    [string]$repo = "",            # Direct input for repository names
    [string]$usernames = "",       # Direct input for usernames
    [string]$permission = "read",  # Default permission (used for direct params only)
    [string]$owner = "Saideep09"   # GitHub organization or user (default is set to 'Saideep09')
)

# Function to read CSV file and return arrays for repositories, usernames, and permissions
function Read-CSVFile {
    param(
        [string]$filePath
    )
    $csvData = Import-Csv -Path $filePath
    $repoNamesArray = $csvData.Repository
    $usernamesArray = $csvData.username
    $permissionsArray = $csvData.permission

    # Debugging: Show what's being read from CSV
    Write-Host "CSV Loaded: Repos: $($repoNamesArray -join ', '), Usernames: $($usernamesArray -join ', '), Permissions: $($permissionsArray -join ', ')"
    return @{ repoNames = $repoNamesArray; usernames = $usernamesArray; permissions = $permissionsArray }
}

# Get GitHub token from environment variables for security
$token = $env:GITHUB_TOKEN  # Securely fetch GitHub token from environment

if (-not $token) {
    Write-Host "Error: GitHub token is missing. Please check your GitHub Actions secret settings."
    exit 1
}

# Function to validate GitHub token
function Test-GitHubToken {
    param (
        [string]$token
    )
    $headers = @{
        Authorization = "Bearer $token"
        Accept        = "application/vnd.github.v3+json"
    }

    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/user" -Method Get -Headers $headers
        if ($response.login) {
            Write-Host "Token is valid. Authenticated as $($response.login)."
            return $true
        }
    } catch {
        Write-Host "Error: Invalid token or insufficient permissions. $($_.Exception.Message)"
        return $false
    }
}

# Function to check if a repository exists in GitHub
function Check-RepositoryExists {
    param (
        [string]$repoName
    )
    $url = "https://api.github.com/repos/$owner/$repoName"
    $headers = @{ 
        Authorization = "Bearer $token"
        Accept = "application/vnd.github.v3+json"
    }

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        Write-Host "Repository $repoName exists."
        return $true
    } catch {
        Write-Host "Repository $repoName does not exist or you don't have access. Error: $($_.Exception.Message)"
        return $false
    }
}

# Function to check if a GitHub username exists
function Check-UsernameExists {
    param (
        [string]$username
    )
    $url = "https://api.github.com/users/$username"
    $headers = @{ 
        Authorization = "Bearer $token"
        Accept = "application/vnd.github.v3+json"
    }

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        Write-Host "Username $username exists."
        return $true
    } catch {
        Write-Host "Username $username does not exist. Error: $($_.Exception.Message)"
        return $false
    }
}

# Call the token validation function
if (-not (Test-GitHubToken -token $token)) {
    Write-Host "Exiting script due to invalid token."
    exit 1
}

# Process CSV if only the CSV file is passed as an argument
if ($filePath -match "\.csv$" -and $repo -eq "" -and $usernames -eq "") {
    Write-Host "Processing input as CSV file..."
    $data = Read-CSVFile -filePath $filePath  # Treat $filePath as the CSV file input
    $repoNamesArray = $data.repoNames
    $usernamesArray = $data.usernames
    $permissionsArray = $data.permissions

    # Loop through CSV and assign the specific permission for each user-repo pair
    for ($i = 0; $i -lt $repoNamesArray.Count; $i++) {
        $repoName = $repoNamesArray[$i]
        $username = $usernamesArray[$i]
        $permission = $permissionsArray[$i]  # Each user-repo pair gets their respective permission

        # Check if repository and username exist before adding
        if (-not (Check-RepositoryExists -repoName $repoName)) {
            Write-Host "Skipping $username due to missing repository: $repoName"
            continue
        }
        if (-not (Check-UsernameExists -username $username)) {
            Write-Host "Skipping $username due to missing username: $username"
            continue
        }

        # Debugging: Show the values being sent to the API
        Write-Host "Adding $username to $repoName with permission $permission"

        # Construct the URL for the API call
        $url = "https://api.github.com/repos/$owner/$repoName/collaborators/$username"

        $headers = @{ 
            Authorization = "Bearer $token"
            Accept = "application/vnd.github.v3+json"
        }
        $body = @{ permission = $permission }

        try {
            # Send the request to add the collaborator
            $response = Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body ($body | ConvertTo-Json)

            # Check the response to determine success
            if ($response) {
                Write-Host "Successfully added $username with '$permission' permission to $repoName."
            } else {
                Write-Host "Failed to add $username. Response: $(ConvertTo-Json $response)"
            }
        } catch {
            # Handle exceptions and print the status code and error message
            Write-Host "API Error: $($_.Exception.Message)"
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = $_.Exception.Response.StatusCode
                Write-Host "Status Code: $statusCode"
                if ($statusCode -eq 403) {
                    Write-Host "Failed: Insufficient permissions to add $username to $repoName."
                } elseif ($statusCode -eq 404) {
                    Write-Host "Failed: Repository or username not found for $username in $repoName."
                }
            }
        }
    }

# Process direct parameters
} elseif ($repo -ne "" -and $usernames -ne "") {
    Write-Host "Processing input as direct parameters..."

    # Split repo names and usernames, and apply the same permission for all users to all repos
    $repoNamesArray = $repo -split ',' | ForEach-Object { $_.Trim() }
    $usernamesArray = $usernames -split ',' | ForEach-Object { $_.Trim() }

    # Loop over all repos and assign all users to each repo with the same permission
    foreach ($repoName in $repoNamesArray) {
        foreach ($username in $usernamesArray) {
            # Check if repository and username exist before adding
            if (-not (Check-RepositoryExists -repoName $repoName)) {
                Write-Host "Skipping $username due to missing repository: $repoName"
                continue
            }
            if (-not (Check-UsernameExists -username $username)) {
                Write-Host "Skipping $username due to missing username: $username"
                continue
            }

            # Debugging: Show the values being sent to the API
            Write-Host "Adding $username to $repoName with permission $permission"

            # Construct the URL for the API call
            $url = "https://api.github.com/repos/$owner/$repoName/collaborators/$username"

            $headers = @{ 
                Authorization = "Bearer $token"
                Accept = "application/vnd.github.v3+json"
            }
            $body = @{ permission = $permission }

            try {
                # Send the request to add the collaborator
                $response = Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body ($body | ConvertTo-Json)

                # Check the response to determine success
                if ($response) {
                    Write-Host "Successfully added $username with '$permission' permission to $repoName."
                } else {
                    Write-Host "Failed to add $username. Response: $(ConvertTo-Json $response)"
                }
            } catch {
                # Handle exceptions and print the status code and error message
                Write-Host "API Error: $($_.Exception.Message)"
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = $_.Exception.Response.StatusCode
                    Write-Host "Status Code: $statusCode"
                    if ($statusCode -eq 403) {
                        Write-Host "Failed: Insufficient permissions to add $username to $repoName."
                    } elseif ($statusCode -eq 404) {
                        Write-Host "Failed: Repository or username not found for $username in $repoName."
                    }
                }
            }
        }
    }

} else {
    Write-Host "Error: No valid input provided. Please provide a CSV file or direct parameters."
    exit 1
}
