resource "random_string" "datagen" {
  length = 10
}

output "myrandstring" {
  value = random_string.datagen.result
}
