<!-- BEGIN_TF_DOCS -->
# Tenant Example
To run this example you need to execute:
```bash
$ terraform init
$ terraform plan
$ terraform apply
```
Note that this example will create resources. Resources can be destroyed with `terraform destroy`.

#### `ndo.yaml`

```hcl
ndo:
  sites:
    - name: APIC1
      id: 1
  tenants:
    - name: NDO1
      sites:
        - name: APIC1
```

#### `main.tf`

```hcl
module "tenant" {
  source  = "netascode/nac-ndo/mso"
  version = "0.1.0"

  yaml_files = ["ndo.yaml"]

  manage_sites   = true
  manage_tenants = true
}
```
<!-- END_TF_DOCS -->