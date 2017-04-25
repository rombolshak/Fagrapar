using System.Management.Automation;
using AngleSharp;

namespace Commands
{
	[Cmdlet("Parse", "Wherevent")]
	public class ParseWherevent : Cmdlet
	{
		[Parameter(Mandatory = true)]
		public string Url { get; set; }

		protected override async void ProcessRecord()
		{
			var config = Configuration.Default.WithDefaultLoader();
			var document = await BrowsingContext.New(config).OpenAsync(Url);
			var events = document.QuerySelectorAll(".event");
			foreach (var @event in events)
			{
				WriteObject(new
				{
					Thumb = @event.QuerySelector("img").Attributes["src"],
					Title = @event.QuerySelector(".event_title").TextContent,
					DateTime = @event.QuerySelector("time").Attributes["datetime"],
					Location = @event.QuerySelector(".event_location").TextContent,
					FemaleCount = @event.QuerySelector(".event_femalecount").TextContent,
					MaleCount = @event.QuerySelector(".event_malecount").TextContent
				});
			}
		}
	}
}
