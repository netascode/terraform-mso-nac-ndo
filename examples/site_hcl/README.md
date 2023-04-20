<!-- BEGIN_TF_DOCS -->
# Site Example
To run this example you need to execute:
```bash
$ terraform init
$ terraform plan
$ terraform apply
```
Note that this example will create resources. Resources can be destroyed with `terraform destroy`.

#### `main.tf`

```hcl
module "site" {
  source  = "netascode/nac-ndo/mso"
  version = "0.1.0"

  model = {
    ndo = {
      sites = [
        {
          name      = "APIC1"
          id        = 1
          apic_urls = ["https://10.1.1.1"]
        }
      ]
    }
  }

  manage_sites = true
}
```
<!-- END_TF_DOCS -->