@testable import Library
@testable import Kickstarter_Framework
@testable import KsApi
@testable import ReactiveExtensions_TestHelpers
import KsApi
import Prelude
import ReactiveCocoa
import Result
import XCTest

final class UpdatePreviewViewModelTests: TestCase {
  private let vm: UpdatePreviewViewModelType = UpdatePreviewViewModel()

  private let showPublishConfirmation = TestObserver<String, NoError>()
  private let showPublishFailure = TestObserver<(), NoError>()
  private let goToUpdate = TestObserver<Update, NoError>()
  private let goToUpdateProject = TestObserver<Project, NoError>()
  private let webViewLoadRequest = TestObserver<String?, NoError>()

  override func setUp() {
    super.setUp()

    self.vm.outputs.showPublishConfirmation.observe(self.showPublishConfirmation.observer)
    self.vm.outputs.showPublishFailure.observe(self.showPublishFailure.observer)
    self.vm.outputs.goToUpdate.map(second).observe(self.goToUpdate.observer)
    self.vm.outputs.goToUpdate.map(first).observe(self.goToUpdateProject.observer)
    self.vm.outputs.webViewLoadRequest.map { $0.URL?.absoluteString }
      .observe(self.webViewLoadRequest.observer)
  }

  func testWebViewLoaded() {
    let draft = .template
      |> UpdateDraft.lens.update.id .~ 1
      |> UpdateDraft.lens.update.projectId .~ 2
    self.vm.inputs.configureWith(draft: draft)
    self.vm.inputs.viewDidLoad()

    let previewUrl = "https://***REMOVED***/projects/2/updates/1/preview"
    let query = "client_id=\(self.apiService.serverConfig.apiClientAuth.clientId)"
    self.webViewLoadRequest.assertValues(
      ["\(previewUrl)?\(query)"]
    )

    let redirectUrl = "https://www.kickstarter.com/projects/smashmouth/somebody-once-told-me/posts/1"
    let policy = self.vm.inputs.decidePolicyFor(
      navigationAction: MockNavigationAction(
        navigationType: .Other,
        request: NSURLRequest(URL: NSURL(string: redirectUrl)!)
      )
    )

    XCTAssertEqual(WKNavigationActionPolicy.Allow.rawValue, policy.rawValue)
    self.webViewLoadRequest.assertValues(
      [
        "\(previewUrl)?\(query)",
        "\(redirectUrl)?\(query)"
      ]
    )
  }

  func testPublishSuccess() {
    let project = .template
      |> Project.lens.id .~ 2
      |> Project.lens.stats.backersCount .~ 1_024
    let draft = .template
      |> UpdateDraft.lens.update.id .~ 1
      |> UpdateDraft.lens.update.projectId .~ project.id

    let api = MockService(fetchProjectResponse: project, fetchUpdateResponse: draft.update)
    withEnvironment(apiService: api) {
      self.vm.inputs.configureWith(draft: draft)
      self.vm.inputs.viewDidLoad()

      self.showPublishConfirmation.assertValues([])
      self.vm.inputs.publishButtonTapped()
      let confirmation =
      "This will notify 1,024 backers that a new update is available. Are you sure you want to post?"
      self.showPublishConfirmation.assertValues([confirmation])

      self.goToUpdate.assertValues([])
      self.goToUpdateProject.assertValues([])
      self.vm.inputs.publishConfirmationButtonTapped()
      self.goToUpdate.assertValues([draft.update])
      self.goToUpdateProject.assertValues([project])
      self.showPublishFailure.assertValueCount(0)
    }
  }

  func testPublishFailure() {
    let project = .template
      |> Project.lens.id .~ 2
      |> Project.lens.stats.backersCount .~ 1_024
    let draft = .template
      |> UpdateDraft.lens.update.id .~ 1
      |> UpdateDraft.lens.update.projectId .~ project.id

    let api = MockService(fetchProjectResponse: project, publishUpdateError: .couldNotParseJSON)
    withEnvironment(apiService: api) {
      self.vm.inputs.configureWith(draft: draft)
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.publishButtonTapped()

      self.showPublishFailure.assertValueCount(0)
      self.vm.inputs.publishConfirmationButtonTapped()
      self.goToUpdate.assertValues([])
      self.showPublishFailure.assertValueCount(1)
    }
  }
}