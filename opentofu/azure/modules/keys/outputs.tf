output "random_string" {
  value = random_password.generated_string.result
  sensitive = true
}
