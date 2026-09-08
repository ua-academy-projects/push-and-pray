resource "google_project_iam_member" "ops_agent" {
  for_each = local.agent_role_members

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
