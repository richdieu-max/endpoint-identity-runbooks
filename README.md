# endpoint-identity-runbooks

Runbooks for Microsoft Intune, Defender for Endpoint, Entra ID and Azure infrastructure, written from procedures I have built and run in regulated environments (pharmaceutical, biotech and compliance software). Each one is generalised: no organisation names, domains, tenant IDs, addresses or people.

Every runbook follows the same shape: what it does and where it stops, a diagram, prerequisites, steps, how to verify, troubleshooting, and the NIST SP 800-53 Rev. 5, NIST CSF 2.0 and ISO/IEC 27001:2022 controls it supports.

## Runbooks

| Runbook | Platform | What it solves |
|---|---|---|
| [Defender for Endpoint on macOS via Intune](runbooks/macos-defender-for-endpoint-via-intune.md) | Intune, Defender for Endpoint | Zero-prompt onboarding of managed Macs: seven permission profiles, onboarding profile, required app, in the right order |
| [Two-person control for device wipe](runbooks/intune-multi-admin-approval-device-wipe.md) | Intune Multi Admin Approval, Entra ID | No single admin can wipe, retire or delete a device; covers the app-permission bypass and how to compensate |
| [Azure tenant foundation](runbooks/azure-tenant-foundation.md) | Entra ID, Azure management groups, Azure Policy | Day-zero identity and governance: break-glass accounts, MFA, domain, policy hierarchy |
| [Point-to-site VPN with Entra ID sign-in](runbooks/azure-p2s-vpn-entra-id.md) | Azure VPN Gateway, Entra ID | Admin RDP to VMs with no public IP, through an MFA-protected OpenVPN tunnel |
| [Two-region backup and DR design](runbooks/azure-backup-dr-two-region.md) | Veeam Backup for Microsoft Azure, Azure Backup, Site Recovery | 4-hour recovery points, immutable off-site copies, tiered RPO/RTO and a test cadence |

## Related

- [azure-posture-check](https://github.com/richdieu-max/azure-posture-check): read-only PowerShell check that verifies many of these settings and writes hashed evidence.
- [security-assessment-toolkit](https://github.com/richdieu-max/security-assessment-toolkit): the workbook I use to record threats, risks and control mappings.

## Notes

- Portal paths change. Each runbook names the setting as well as the path so it can be found after a redesign.
- A control mapping means the procedure supports that control. It does not certify compliance on its own.

## License

MIT. See [LICENSE](LICENSE).
