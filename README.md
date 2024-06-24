Sure! Here’s a detailed README file for your Intune Toolkit GitHub repository.

---

# Intune Toolkit

## Overview

The Intune Toolkit is a PowerShell-based solution designed to simplify the management of Microsoft Intune policies. It provides a user-friendly interface for connecting to Microsoft Graph, managing device configuration policies, compliance policies, mobile applications, and more. The toolkit supports functionalities like backing up and restoring policies, and adding or deleting assignments, with robust error handling and detailed logging.

![alt text](image.png)

## Features

- Connect to Microsoft Graph with necessary scopes.
- Display tenant information and signed-in user details.
- Load, backup, and restore various types of policies:
  - Configuration Policies
  - Device Compliance Policies
  - Mobile Applications
  - Administrative Templates
- Add and delete assignments for selected policies.
- Detailed logging for all major actions and error handling.
- User-friendly selection dialog for groups and filters.

## Prerequisites

- PowerShell 5.1 or later.
- Microsoft Graph PowerShell SDK.
- Windows Presentation Framework (WPF) for the GUI components.
- Access to Microsoft Intune and the necessary permissions.

## Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/yourusername/Intune-Toolkit.git
   cd Intune-Toolkit
   ```

2. Install the Microsoft Graph PowerShell SDK:
   ```sh
   Install-Module Microsoft.Graph -Scope CurrentUser
   ```

3. Ensure you have the required assemblies and permissions to run the toolkit.

## Usage

1. **Launch the Main Script:**
   ```sh
   .\Main.ps1
   ```

2. **Connect to Microsoft Graph:**
   - Click the "Connect" button to sign in and authorize the toolkit with the necessary scopes.

3. **Manage Policies:**
   - Select the type of policy you want to manage (e.g., Configuration Policies, Device Compliance Policies, etc.) using the corresponding buttons.
   - View and manage the assignments for the selected policies.

4. **Backup Policies:**
   - Click the "Backup" button to save the current policies to a JSON file.

5. **Restore Policies:**
   - Click the "Restore" button to load policies from a backup file.

6. **Add/Remove Assignments:**
   - Use the "Add Assignment" and "Delete Assignment" buttons to manage assignments for the selected policies.

## File Structure

- **Main.ps1**: The main script that initializes the application, loads the UI, and imports other scripts.
- **Scripts/**: Contains all the function scripts for various actions.
  - **Functions.ps1**: Contains common functions used across the toolkit.
  - **ConnectButton.ps1**: Handles the connect button click event.
  - **LogoutButton.ps1**: Handles the logout button click event.
  - **ConfigurationPoliciesButton.ps1**: Handles loading configuration policies.
  - **DeviceConfigurationButton.ps1**: Handles loading device configurations.
  - **ComplianceButton.ps1**: Handles loading compliance policies.
  - **AdminTemplatesButton.ps1**: Handles loading administrative templates.
  - **ApplicationsButton.ps1**: Handles loading applications.
  - **DeleteAssignmentButton.ps1**: Handles deleting assignments.
  - **AddAssignmentButton.ps1**: Handles adding assignments.
  - **BackupButton.ps1**: Handles backing up policies.
  - **RestoreButton.ps1**: Handles restoring policies.
  - **Show-SelectionDialog.ps1**: Displays the selection dialog for groups and filters.
  - **SearchButton.ps1**: Handles search functionality.
- **XML/**: Contains XAML files for defining the UI layout.
  - **Main.xaml**: XAML file for the main window layout.
  - **SelectionDialog.xaml**: XAML file for the selection dialog layout.
- **Logs/**: Contains the log files generated during the execution of the toolkit.

## Logging

The toolkit logs all major actions and errors to `IntuneToolkit.log`. Each log entry includes a timestamp, component, context, type, thread, and file information to help with troubleshooting and tracking activities.

## Contributing

Contributions are welcome! Please fork the repository and submit pull requests for any enhancements or bug fixes. Ensure your code adheres to the existing style and includes appropriate logging and error handling.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Microsoft Graph PowerShell SDK for providing the necessary APIs to manage Intune.
- The PowerShell community for their invaluable resources and support.
