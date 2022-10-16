### What's this script is about?
If you have multiple environments (Prod, QA, Dev, etc) in your organization, there must be multiple SendGrid Accounts as well for maintaining email templates changes for your application releases. So, when the production day arrived you must be struggling manually copying these email templates changes from Dev SendGrid account to Prod SendGrid account. Which is slow, messy, and prone to errors. 

### What's this script Do?
- Copying changes from one SendGrid account (SOURCE) to other SendGrid Account (TARGET)
- Update only changed templates from SOURCE account (WHERE SOURCE.Template.LastModifiedDate > TARGET.Template.LastModifiedDate)
- Create new template on TARGET account if non found
- Skip updating TARGET account templates if it's updated manually (WHERE TARGET.Template.LastModifiedDate < SOURCE.Template.LastModifiedDate)
- Support any SendGrid account type - You can pick whether your SendGrid account type is Legacy or not by using parameter.
- CI/CD friendly - Because this is a simple powershell script, this can be easily run on any CI/CD tool
