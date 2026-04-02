# Rails: Active Storage

## Pattern

Active Storage handles file uploads in Rails — attaching files to models, processing variants (thumbnails, resizes), and storing them on local disk, S3, GCS, or Azure. Configure it once, use it through a clean model API.

```ruby
# Setup
# rails active_storage:install
# rails db:migrate

# config/storage.yml
local:
  service: Disk
  root: <%= Rails.root.join("storage") %>

amazon:
  service: S3
  access_key_id: <%= ENV["AWS_ACCESS_KEY_ID"] %>
  secret_access_key: <%= ENV["AWS_SECRET_ACCESS_KEY"] %>
  region: us-east-1
  bucket: rubyn-uploads

# config/environments/development.rb
config.active_storage.service = :local

# config/environments/production.rb
config.active_storage.service = :amazon
```

### Model Attachments

```ruby
class User < ApplicationRecord
  has_one_attached :avatar
  has_one_attached :resume

  # Validations (use activestorage-validator gem or custom)
  validate :avatar_format

  private

  def avatar_format
    return unless avatar.attached?

    unless avatar.content_type.in?(%w[image/png image/jpeg image/webp])
      errors.add(:avatar, "must be PNG, JPEG, or WebP")
    end

    if avatar.byte_size > 5.megabytes
      errors.add(:avatar, "must be under 5MB")
    end
  end
end

class Order < ApplicationRecord
  has_many_attached :documents  # Multiple files

  has_one_attached :invoice_pdf
end
```

### Controller and Form

```ruby
class UsersController < ApplicationController
  def update
    @user = current_user

    if @user.update(user_params)
      redirect_to @user, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :avatar)
  end
end
```

```erb
<%# Form — standard file field, nothing special %>
<%= form_with model: @user do |f| %>
  <%= f.file_field :avatar, accept: "image/png,image/jpeg,image/webp" %>

  <% if @user.avatar.attached? %>
    <%= image_tag @user.avatar.variant(resize_to_limit: [200, 200]) %>
    <%= button_to "Remove", purge_avatar_user_path(@user), method: :delete %>
  <% end %>

  <%= f.submit "Save" %>
<% end %>
```

### Variants (Image Processing)

```ruby
# Requires: gem "image_processing", "~> 1.2"

class User < ApplicationRecord
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [100, 100]
    attachable.variant :medium, resize_to_limit: [300, 300]
    attachable.variant :large, resize_to_limit: [800, 800]
  end
end

# Usage in views
<%= image_tag @user.avatar.variant(:thumb) %>
<%= image_tag @user.avatar.variant(:medium) %>

# Custom one-off variant
<%= image_tag @user.avatar.variant(resize_to_limit: [150, 150], format: :webp) %>

# Check before rendering
<% if @user.avatar.attached? %>
  <%= image_tag @user.avatar.variant(:thumb) %>
<% else %>
  <%= image_tag "default_avatar.png" %>
<% end %>
```

### Direct Uploads (Client-Side)

```javascript
// app/javascript/application.js
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()
```

```erb
<%# Direct upload — file goes straight to storage, not through your server %>
<%= form.file_field :avatar, direct_upload: true %>
```

Direct uploads send the file directly to S3/GCS from the browser. Your server only receives the signed blob ID, not the file bytes. This keeps your web server fast and avoids upload timeouts.

### Service Objects for Complex Uploads

```ruby
# When upload involves processing, validation, or multiple steps
class Documents::UploadService
  def self.call(order, file)
    new(order, file).call
  end

  def initialize(order, file)
    @order = order
    @file = file
  end

  def call
    validate_file!
    @order.documents.attach(@file)
    process_document(@order.documents.last)
    Result.new(success: true)
  rescue ActiveStorage::IntegrityError => e
    Result.new(success: false, error: "File corrupted: #{e.message}")
  rescue DocumentTooLargeError => e
    Result.new(success: false, error: e.message)
  end

  private

  def validate_file!
    raise DocumentTooLargeError, "File exceeds 25MB" if @file.size > 25.megabytes
  end

  def process_document(attachment)
    # Extract text, generate preview, scan for viruses — async
    DocumentProcessingJob.perform_later(attachment.id)
  end
end
```

## Why This Is Good

- **One API for every storage backend.** Develop with local disk, deploy with S3. Change one line in config, not your code.
- **Variants are lazy.** `variant(:thumb)` doesn't process the image until it's first requested. After that, the processed variant is cached.
- **Direct uploads offload your server.** Large files go straight to S3 from the browser. Your Rails app never touches the bytes.
- **Attachment validations on the model.** File type and size checks happen before save, with standard error messages on the model.
- **Named variants are reusable.** Define `:thumb`, `:medium`, `:large` once on the model, use them everywhere in views.

## Anti-Pattern

```ruby
# BAD: Processing uploads in the controller
def create
  file = params[:document]
  File.open(Rails.root.join("uploads", file.original_filename), "wb") do |f|
    f.write(file.read)
  end
  # Manual file management, no cleanup, no variants, no cloud storage

  # BAD: Synchronous processing on upload
  @user.avatar.attach(params[:avatar])
  ImageOptimizer.new(@user.avatar).optimize!  # Blocks the request for 5 seconds
  ThumbnailGenerator.new(@user.avatar).generate!  # Another 3 seconds
end
```

## When To Apply

- **Every file upload in a Rails app.** Active Storage replaces CarrierWave, Paperclip, and Shrine for most use cases.
- **User avatars, document uploads, image galleries.** Standard Active Storage with variants.
- **Large files (>10MB).** Use direct uploads to avoid tying up web workers.

## When NOT To Apply

- **Extremely complex image processing pipelines.** If you need 20+ variant types, watermarking, face detection — consider Shrine or a dedicated image service.
- **Non-Rails apps.** Active Storage is Rails-only. Use Shrine or direct S3 SDK calls for Sinatra/plain Ruby.
- **Temporary file processing.** If you're processing a CSV and discarding it, don't attach it to a model. Just use `Tempfile`.

## Edge Cases

**Purging attachments:**
```ruby
@user.avatar.purge        # Deletes synchronously
@user.avatar.purge_later  # Deletes via background job (preferred)
```

**Preloading to avoid N+1:**
```ruby
# BAD: N+1 on avatars
users.each { |u| image_tag u.avatar } # Each avatar is a separate query

# GOOD: Preload
users = User.with_attached_avatar
```

**Attaching from a URL:**
```ruby
@user.avatar.attach(
  io: URI.open("https://example.com/photo.jpg"),
  filename: "photo.jpg",
  content_type: "image/jpeg"
)
```
