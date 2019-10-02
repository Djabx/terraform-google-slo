/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

resource "google_pubsub_topic" "stream" {
  project = var.project_id
  name    = var.pubsub_topic_name
}

resource "local_file" "exporters" {
  content  = jsonencode(var.exporters)
  filename = "${path.module}/code/exporters.json"
}

data "archive_file" "main" {
  type        = "zip"
  output_path = pathexpand("${path.module}/code.zip")
  source_dir  = pathexpand("${path.module}/code")
}

resource "google_bigquery_dataset" "main" {
  count                       = length(local.bigquery_configs)
  project                     = local.bigquery_configs[count.index].project_id
  dataset_id                  = local.bigquery_configs[count.index].dataset_id
  delete_contents_on_destroy  = lookup(local.bigquery_configs[count.index], "delete_contents_on_destroy", false)
  location                    = lookup(local.bigquery_configs[count.index], "location", "EU")
  friendly_name               = "SLO Reports"
  description                 = "Table storing SLO reports from SLO reporting pipeline"
  default_table_expiration_ms = 525600000 # 1 year
}

resource "google_storage_bucket" "bucket" {
  name    = var.bucket_name
  project = var.project_id
}

resource "google_storage_bucket_object" "main" {
  name                = "slo_exporter.zip"
  bucket              = google_storage_bucket.bucket.name
  source              = data.archive_file.main.output_path
  content_disposition = "attachment"
  content_encoding    = "gzip"
  content_type        = "application/zip"
}

resource "google_cloudfunctions_function" "function" {
  description           = "SLO Exporter to BigQuery or Stackdriver Monitoring"
  name                  = var.function_name
  available_memory_mb   = var.function_memory
  project               = var.project_id
  region                = var.region
  service_account_email = google_service_account.main.email
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.main.name
  runtime               = "python37"
  timeout               = "60"
  entry_point           = "main"
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = "projects/${var.project_id}/topics/${google_pubsub_topic.stream.name}"
  }
}