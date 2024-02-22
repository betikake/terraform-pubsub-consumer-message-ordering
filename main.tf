terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 4.84.0"
    }
  }
}

resource "google_pubsub_schema" "default" {
  name = var.schema_name
  type = "PROTOCOL_BUFFER"

  definition = file("${path.cwd}/${var.schema_definition}")
}

resource "google_pubsub_topic" "default" {
  name = var.pubsub_topic

  schema_settings {
    schema   = "projects/${var.fun_project_id}/schemas/${google_pubsub_schema.default.name}"
    encoding = "BINARY"

  }
}

resource "google_pubsub_topic" "default_dlq" {
  name = "${var.pubsub_topic}_dlq"
}

resource "google_pubsub_subscription" "default" {
  name  = var.pubsub_topic
  topic = google_pubsub_topic.default.name

  push_config {
    push_endpoint = "${google_cloudfunctions2_function.default.service_config[0].uri}?__GCP_CloudEventsMode=CUSTOM_PUBSUB_projects%2F${var.fun_project_id}%2Ftopics%2F${var.pubsub_topic}"
    oidc_token {
      # a new IAM service account is need to allow the subscription to trigger the function
      service_account_email = var.service_account_email
      audience              = "${google_cloudfunctions2_function.default.service_config[0].uri}/"
    }
  }
  enable_message_ordering = true
  ack_deadline_seconds    = 600

  dead_letter_policy {
    dead_letter_topic = google_pubsub_topic.default_dlq.id
    max_delivery_attempts = 10
  }
}

resource "google_pubsub_subscription" "default_dlq" {
  name  = "${var.pubsub_topic}_dlq"
  topic = google_pubsub_topic.default_dlq.name

  enable_message_ordering = true
  ack_deadline_seconds    = 600
}

resource "random_id" "bucket_prefix" {
  byte_length = var.bucket_prefix_length
}

module "archive" {
  source     = "git::https://github.com/betikake/terraform-archive"
  source_dir = var.source_dir
}

module "bucket" {
  source          = "git::https://github.com/betikake/terraform-bucket"
  bucket_name     = var.source_bucket_name
  location        = var.fun_location
  output_sha      = module.archive.output_sha
  source_code     = module.archive.source
  output_location = module.archive.output_path
  function_name   = var.function_name
}


resource "google_cloudfunctions2_function" "default" {
  name        = lower(var.function_name)
  description = var.description
  project     = var.fun_project_id
  location    = var.region


  build_config {
    runtime     = var.run_time
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = module.bucket.bucket_name
        object = module.bucket.bucket_object
      }
    }
  }

  /* lifecycle {
     replace_triggered_by  = [
       terraform_data.replacement
     ]
   }*/

  labels = {
    version-crc32c = lower(replace(module.bucket.crc32c, "/\\W+/", ""))
  }


  service_config {
    available_memory                 = var.available_memory
    available_cpu                    = var.available_cpu
    max_instance_request_concurrency = var.max_instance_request_concurrency
    vpc_connector                    = var.vpc_connector
    service_account_email            = var.service_account_email
    max_instance_count               = var.max_instance
    min_instance_count               = var.min_instance
    all_traffic_on_latest_revision   = true
    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    environment_variables            = var.environment_variables
    timeout_seconds                  = var.timeout
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.default.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

}


/*
output "function_location" {
  value       = var.trigger_type == "pubsub" ? var.pubsub_topic : google_cloudfunctions2_function.default.location
  description = var.trigger_type == "pubsub" ? "Pub/Sub topic" : "URL of the Cloud Function"
}
*/
