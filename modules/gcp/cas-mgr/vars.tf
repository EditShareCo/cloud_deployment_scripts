/*
 * Copyright Teradici Corporation 2020-2022;  © Copyright 2022 HP Development Company, L.P.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

variable "gcp_service_account" {
  description = "Service Account in the GCP Project"
  type        = string
}

variable "prefix" {
  description = "Prefix to add to name of new resources"
  default     = ""
}

variable "pcoip_registration_code" {
  description = "PCoIP Registration code"
  type        = string
  sensitive   = true
}

variable "bucket_name" {
  description = "Name of bucket to retrieve provisioning script."
  type        = string
}

variable "cas_mgr_deployment_sa_file" {
  description = "Filename of CAS Manager Deployment Service Account JSON key in bucket"
  type        = string
}

variable "gcp_sa_file" {
  description = "Filename of GCP Service Account JSON key in bucket (Optional)"
  default     = ""
}

variable "gcp_region" {
  description = "GCP Region to deploy the CAS Managers"
  type        = string
}

variable "gcp_zone" {
  description = "GCP Zone to deploy the CAS Managers"
  type        = string
}

variable "subnet" {
  description = "Subnet to deploy the CAS Managers"
  type        = string
}

variable "enable_public_ip" {
  description = "Assign a public IP to CAS Manager"
  type        = bool
  default     = true
}

variable "network_tags" {
  description = "Tags to be applied to the CAS Manager"
  type        = list(string)
}

variable "host_name" {
  description = "Name to give the host"
  default     = "vm-cas-mgr"
}

variable "machine_type" {
  description = "Machine type for the CAS Manager (min 8 GB RAM, 4 CPUs)"
  default     = "e2-custom-4-8192"
}

variable "disk_size_gb" {
  description = "Disk size (GB) of the CAS Manager (min 60 GB)"
  default     = "60"
}

variable "disk_image" {
  description = "Disk image for the CAS Manager"
  default     = "projects/rocky-linux-cloud/global/images/family/rocky-linux-8"
}

variable "cas_mgr_admin_user" {
  description = "Username of the CAS Manager Administrator"
  type        = string
}

variable "cas_mgr_admin_ssh_pub_key_file" {
  description = "SSH public key for the CAS Manager Administrator"
  type        = string
}

variable "cas_mgr_admin_password" {
  description = "Password for the Administrator of CAS Manager"
  type        = string
  sensitive   = true
}

variable "teradici_download_token" {
  description = "Token used to download from Teradici"
  default     = "yj39yHtgj68Uv2Qf"
}

variable "kms_cryptokey_id" {
  description = "Resource ID of the KMS cryptographic key used to decrypt secrets, in the form of 'projects/<project-id>/locations/<location>/keyRings/<keyring-name>/cryptoKeys/<key-name>'"
  default     = ""
}

variable "ops_setup_script" {
  description = "The script that sets up the GCP Ops Agent"
  type        = string
}

variable "gcp_ops_agent_enable" {
  description = "Enable GCP Ops Agent for sending logs to GCP"
  default     = true
}
