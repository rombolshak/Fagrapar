using System.Management.Automation;
using System.Net;
using AngleSharp.Parser.Html;

namespace Commands
{
	[Cmdlet("Parse", "Wherevent")]
	public class ParseWherevent : Cmdlet
	{
		[Parameter(Mandatory = true)]
		public string Url { get; set; }

		protected override void ProcessRecord()
		{
			var client = new WebClient();
			var response = client.DownloadString(Url);
			var parser = new HtmlParser();
			var document = parser.Parse(response);
			var events = document.QuerySelectorAll(".event");
			foreach (var @event in events)
			{
				WriteObject(new
				{
					Thumb = @event.QuerySelector("img").Attributes["src"],
					Title = @event.QuerySelector(".event_title").TextContent,
					DateTime = @event.QuerySelector("time").Attributes["datetime"],
					Location = @event.QuerySelector(".event_location").TextContent.Trim(),
					FemaleCount = @event.QuerySelector(".event_femalecount").TextContent,
					MaleCount = @event.QuerySelector(".event_malecount").TextContent
				});
			}
		}
	}
}
