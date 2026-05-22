resource "random_string" "datagen" {
  length = 10
}

resource "random_integer" "rint" {
  min = 10
  max = 100
}
