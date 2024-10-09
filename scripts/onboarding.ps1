param(
    [string]$filePath = "",       # Path to the CSV file (optional)
    [string]$organizations = "",  # Direct organization input (optional)
    [string]$usernames = "",      # Direct usernames input (optional)
    [string]$role = ""            # Role input (optional)
)

$token = $env:GITHUB_TOKEN  # GitHub token for authentication

# Function to invite users to organizations
function Invite-Users {
    param (
        [array]$organizations,
        [array]$usernames,
        [string]$role
    )

    foreach ($org in $organizations) {
        foreach ($username in $usernames) {
            $url = "https://api.github.com/orgs/$org/invitations"
            $headers = @{
                Authorization = "token $token"
                Accept        = "application/vnd.github.v3+json"
            }

            # Get User ID for the invitee
            try {
                $userResponse = Invoke-RestMethod -Uri "https://api.github.com/users/$username" -Method Get -Headers $headers
                if (-not $userResponse.id) {
                    Write-Host "Error: No user found with the username $username."
                    continue
                }
                $userId = $userResponse.id
            } catch {
                Write-Host "Failed to retrieve user ID for $username. Error: $($_.Exception.Message)"
                continue
            }

            # Prepare the invitation request body
            $body = @{
                invitee_id = $userId
                role       = $role
            }

            # Send the invitation
            try {
                $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body ($body | ConvertTo-Json)

                if ($response -and $response.id -and $response.login -and $response.created_at) {
                    Write-Host "Successfully invited $username as a '$role' to the organization $org."
                } else {
                    Write-Host "Invitation failed for $username. Response: $(ConvertTo-Json $response)"
                }
            } catch {
                Write-Host "Failed to invite $username to the organization $org. Error: $($_.Exception.Message)"
            }
        }
    }
}

# Process CSV file
if ($filePath -ne "") {
    # CSV file provided: read from the CSV
    Write-Host "Processing CSV file: $filePath"
    $csvData = Import-Csv -Path $filePath

    foreach ($row in $csvData) {
        Invite-Users -organizations @($row.organization) -usernames @($row.username) -role $row.role
    }

# Process direct parameters
} elseif ($organizations -ne "" -and $usernames -ne "" -and $role -ne "") {
    # Direct parameters provided: split the input values
    $orgArray = $organizations -split ','
    $userArray = $usernames -split ','

    Write-Host "Processing direct parameters..."
    Invite-Users -organizations $orgArray -usernames $userArray -role $role

} else {
    Write-Host "Error: No valid input provided. Either a CSV file or direct parameters must be supplied."
    exit 1
}
