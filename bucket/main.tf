resource "random_uuid" "my_uuid" { }


resource "google_storage_bucket" "default" {
  name                        = "${var.function_name}-gcf-source" # Every bucket name must be globally unique
  location                    = var.location
  uniform_bucket_level_access = true
  project                     = var.img_project_id
}


resource "google_storage_bucket_object" "default" {
  name   = "${var.function_name}-gcf-source/function-source-${var.output_sha}.zip"
  bucket = var.bucket_name
  source = var.output_location
}

output "object_value" {
  value = google_storage_bucket_object.default
}

output "bucket_name" {
  value       = var.bucket_name
  description = "The name of the Google Cloud Storage bucket."
}

output "bucket_object" {
  value       = google_storage_bucket_object.default.name
  description = "The object path of the function source code in the Google Cloud Storage bucket."
}

output "crc32c" {
  value       = google_storage_bucket_object.default.md5hash
  description = "crc32c of the bucket"
}